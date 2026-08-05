// Tool Executor Service — Kai's agentic function calling dispatcher.
//
// Tool *schemas* (toolDefinitions) are injected into every GPT chat call.
// When GPT decides to call a tool, the result comes here to be executed.
// Dart-side tools are handled directly; Android system actions are
// delegated to KaiToolsPlugin via the 'com.homecoming.app/kai_tools' channel.
//
// Tool name mapping:
//   snake_case (GPT-facing)  →  camelCase (Android method name)

import 'dart:async'; // unawaited — recording a failure must never cause one
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../ai/ai_config.dart';
import '../ai/claude_service.dart';
import '../ai/claude_code_agent.dart';
import '../ai/contemplation_service.dart';
import '../ai/google_search_service.dart';
import '../ai/usage_tracking_service.dart';
import 'cortex_activity_bus.dart';
import 'code_workspace_service.dart';
import 'kai_craft_service.dart';
import 'kai_second_opinion_service.dart';
import 'edit_gate.dart';
import 'web_fetch_service.dart';
import 'kai_goal_service.dart';
import 'kai_user_model_service.dart';
import 'kai_self_service.dart';
import 'kai_self_context.dart';
import 'kai_self_revision.dart';
import 'kai_autobiography_service.dart';
import 'brain_extraction_service.dart';
import 'kai_job_service.dart';
import 'kai_noticed_service.dart';
import 'kai_project_service.dart';
import 'kai_self_improvement_runner.dart';
import 'kai_bond_service.dart';
import 'kai_embodiment_service.dart';
import 'kai_db.dart';
import 'kai_factory_service.dart';
import 'gumroad_cli_service.dart';
import '../../logic/product_factory.dart';
import '../../logic/product_scout.dart';
import '../../logic/frozen_paths.dart';
import '../../logic/scout_learning.dart';
import 'tool_policy_service.dart';
import '../brain_debug_service.dart';
import '../core/trace_store_service.dart';
import '../../tools/replay.dart';
import '../smarthome/network_discovery_service.dart';
import '../smarthome/smart_tv_service.dart';

enum KaiHandsState { off, activating, on }

enum ToolOutcome {
  passed,
  failed,
  unknown,
  recorded;

  String get label => name;
}

class ToolExecutorService {
  static const _channel = MethodChannel('com.homecoming.app/kai_tools');

  static int inputBreakdownScanLimitFor(int limit) =>
      (limit * 25).clamp(100, 500).toInt();

  static String compactRunTestRaw(String raw) {
    const headMax = 3000;
    const tailMax = 5000;
    if (raw.length <= headMax + tailMax) return raw;
    final cut = raw.length - headMax - tailMax;
    return '${raw.substring(0, headMax)}\n'
        '… [truncated $cut chars — keeping tail because test failures usually end there]\n'
        '${raw.substring(raw.length - tailMax)}';
  }

  // ── Tool schemas — injected into every GPT API call ──────────────────────
  //
  // These tools live in the Android host app behind a MethodChannel. On desktop
  // they throw MissingPluginException, so Kai must never be OFFERED them there:
  // an "all-powerful assistant" that confidently reaches for your alarms and
  // faceplants looks incompetent. Better to not claim a power than to claim it
  // and fail. (Kai's desktop reach is the engineer/web/memory toolset instead.)
  static const Set<String> androidOnlyTools = {
    'set_alarm',
    'set_timer',
    'set_reminder',
    'read_calendar',
    'create_calendar_event',
    'open_app',
    'send_whatsapp',
    'send_sms',
    'call_contact',
    'navigate_to',
    'play_music',
    'read_notifications',
    'read_screen',
  };

  /// Platform-filtered schemas. `kaiDbUsesRest` is true on Windows/Linux/macOS.
  static List<Map<String, dynamic>> get toolDefinitions {
    if (!kaiDbUsesRest)
      return _allToolDefinitions; // phone: full body available
    return _allToolDefinitions.where((t) {
      final name = toolName(t);
      return name == null || !androidOnlyTools.contains(name);
    }).toList(growable: false);
  }

  /// The exact OpenAI function name carried by a tool definition.
  ///
  /// Keep name extraction in one place: route filtering, diagnostics, and tests
  /// must inspect the same nested `function.name` field that the API receives.
  static String? toolName(Map<String, dynamic> definition) {
    final function = definition['function'];
    final name = function is Map ? function['name'] : null;
    return name is String && name.isNotEmpty ? name : null;
  }

  static List<String> toolNames(Iterable<Map<String, dynamic>> definitions) =>
      definitions.map(toolName).whereType<String>().toList(growable: false);

  /// Request-specific awareness of the hands actually attached to a model call.
  /// The API manifest is capability; this block makes that capability conscious.
  static String toolAwarenessBlock(Iterable<String> toolNames) {
    final names = toolNames.toList(growable: false);
    if (names.isEmpty) {
      return 'CURRENT TOOLS: none are attached to this model request. Do not '
          'claim or attempt tool use on this turn.';
    }
    final canSetWorkspace = names.contains('set_code_workspace');
    final hasCodeHands = names.contains('read_file');
    final workspaceRecovery = canSetWorkspace && !hasCodeHands
        ? '''

WORKSPACE RECOVERY: You do not have repo hands yet, but you DO have
set_code_workspace. If the user asks you to inspect, fix, or build code, call
set_code_workspace immediately instead of reporting that the tools are missing.
Briefly say "I'm activating my hands" as progress narration while you do it.
After it succeeds, the next agent iteration will automatically refresh this
manifest and give you read_file/edit_file/run_command/self_check/run_tests.'''
        : '';
    return '''CURRENT TOOLS — THESE ARE REAL AND ATTACHED TO THIS REQUEST:
${names.map((name) => '- $name').join('\n')}

You have these tools now. Their function schemas below are the source of truth.
When the user asks for work one of them can perform, use it instead of merely
describing the work, claiming you lack access, or asking the user to do it.
Never claim a tool that is absent from this exact list.$workspaceRecovery''';
  }

  static KaiHandsState handsStateForTools(Iterable<String> toolNames) {
    final names = toolNames.toSet();
    if (names.containsAll(desktopCodingToolNames)) return KaiHandsState.on;
    if (names.contains('set_code_workspace')) return KaiHandsState.activating;
    return KaiHandsState.off;
  }

  /// Minimum hands a desktop coding turn must carry once a workspace is set.
  static const Set<String> desktopCodingToolNames = {
    'read_file',
    'write_file',
    'edit_file',
    'run_command',
    'self_check',
    'run_tests',
    'job_start',
    'job_progress',
    'job_done',
  };

  // ── Route-aware tools ──────────────────────────────────────────────────────
  //
  // The tool schemas are ~35,000 characters — roughly 9,000 tokens — and they
  // ship on EVERY turn. His entire personality (presenceDirective + northStar +
  // readTheRoom) is ~3,400 characters. So he spends about 6% of his system
  // prompt being himself and the rest carrying a toolbox, most of which is
  // irrelevant to whatever he's doing right now.
  //
  // That's the cost of being Kai, and it's paid on "yo".
  //
  // ── The direction matters, and the obvious version is wrong ───────────────
  //
  // The tempting move is "fastChat → no tools". It's a trap. fastChat is the
  // DEFAULT in KaiRouterService — `route = fastChat, confidence = 0.35` — so
  // every unmatched phrasing lands there. "can you ping mikey" doesn't match
  // the 'message ' signal. Strip tools on fastChat and he says "I can't" about
  // something he can do. Trading capability for tokens on the one route that
  // catches everything is how you turn an all-powerful assistant into a
  // chatbot that apologises.
  //
  // So: only ever strip from a CONFIDENT route, and only tools that are
  // obviously irrelevant to it. When he's coding at 86% confidence he does not
  // need control_tv, discover_tvs or play_music. If we misroute, the cost is
  // one "ask me again" — not a silent lie about his own hands.
  //
  // Never strips: the core (time/weather/search/fetch), memory, bond, goals,
  // self. Those get reached for without warning in any conversation.

  /// Hands. Useless without a workspace, irrelevant to comfort or small talk.
  static const _engineeringTools = <String>{
    'code_task',
    'set_code_workspace',
    'read_file',
    'list_dir',
    'find_files',
    'search_code',
    'edit_file',
    'write_file',
    'run_command',
    'open_terminal',
    'self_check',
    'run_tests',
    'usage_report',
    'input_breakdown',
    'job_start',
    'job_progress',
    'job_done',
    'set_layer_progress',
    'set_checklist_status',
    'run_self_improvement_loop',
  };

  /// Product-factory ledger and gates. These are not workspace hands: a factory
  /// run still needs its start/status/record spine even when the actual product
  /// research is a web-heavy product route rather than a coding route.
  static const _factoryTools = <String>{
    'scout_score', 'factory_start', 'factory_status', 'factory_record',
    'factory_advance', 'factory_abandon', 'storefront_publish',
    'storefront_sales', 'factory_learn',
    // The learning policy. `scout_record_attempt` is the one that must never be
    // skipped on a FAILED attempt — a failure that goes unrecorded is the only
    // kind that teaches nothing, and turns the loop into paid repetition.
    'scout_record_attempt', 'scout_policy', 'usage_report',
  };

  /// The subset of the hands that CHANGE something.
  ///
  /// This split exists because of one trace. Sadeq asked "so, what do you
  /// think we should do next?", the router called it contemplate at 78% — a
  /// correct read — and he was handed 36 of 39 tools anyway, including
  /// edit_file and run_command. He answered well and used none of them, but
  /// that's luck, not design: put a workshop in front of someone and ask their
  /// opinion, and some of the time you get carpentry instead of an answer.
  ///
  /// Reading is NOT in here on purpose. Taking his eyes away while asking him
  /// what he thinks is how you get a confident guess, and confident guessing
  /// is the exact disease the rest of this file is medicine for. He can look.
  /// He just shouldn't be able to start building mid-sentence.
  static const _mutatingTools = <String>{
    'code_task',
    'set_code_workspace',
    'edit_file',
    'write_file',
    'run_command',
    'open_terminal',
  };

  /// Phone/body actions.
  static const _deviceTools = <String>{
    'read_screen',
    'read_notifications',
    'read_calendar',
    'create_calendar_event',
    'set_alarm',
    'set_timer',
    'set_reminder',
    'open_app',
    'send_whatsapp',
    'send_sms',
    'call_contact',
    'navigate_to',
    'play_music',
  };

  /// The house.
  static const _homeTools = <String>{
    'control_tv',
    'control_device',
    'discover_tvs',
  };

  /// Schemas for a given route.
  ///
  /// [route] is the KaiRoute name ('fastChat' | 'tool' | 'coding' | 'emotional'
  /// | 'contemplate') — passed as a string so this file doesn't have to depend
  /// on the router. [confidence] guards the whole thing: a low-confidence
  /// classification strips NOTHING, because a guess should never cost him a
  /// hand.
  /// [hasWorkspace] false means the engineering tools cannot work at all — his
  /// own engineerDirective says so ("when a workspace is set") — so carrying
  /// their schemas is pure tax.
  static List<Map<String, dynamic>> toolsForRoute(
    String route, {
    double confidence = 0.0,
    bool hasWorkspace = true,
  }) {
    final all = toolDefinitions;
    final drop = <String>{};

    // Hands he doesn't have. True regardless of route or confidence.
    //
    // ── EXCEPT the tool that GIVES him hands. ────────────────────────────────
    // This line used to drop ALL of _engineeringTools, and set_code_workspace
    // is in that set — so with no workspace loaded, the manifest stripped the
    // one tool that sets a workspace, while KaiContextBlock block [6] was
    // simultaneously telling him "set_code_workspace first". A catch-22: he
    // could never comply with his own prompt. Layer 2 all over again — his own
    // policy registry eating his hands. The setter must survive precisely when
    // hasWorkspace is false, because that is the only moment it matters.
    if (!hasWorkspace) {
      drop.addAll(_engineeringTools.where((t) => t != 'set_code_workspace'));
    }

    // fastChat is the catch-all, not evidence that this is non-coding. Sadeq's
    // short follow-ups ("fix it", "go on", "what tools do you have?") routinely
    // land here at low confidence. Stripping the engineering manifest made Kai
    // truthfully report that he had tools but not his repo hands. When a desktop
    // workspace exists, uncertainty must preserve capability; only a known
    // no-workspace state or a confident route may remove tools.

    // Only act on a route we actually believe. fastChat's floor is 0.35 and
    // it's the catch-all — the cheap-default block above handles it separately.
    if (confidence >= 0.75) {
      switch (route) {
        case 'coding':
          drop
            ..addAll(_deviceTools)
            ..addAll(_homeTools);
        case 'emotional':
          // Engineering and the house are noise here. Device stays: "call my
          // brother" is a completely reasonable thing to want mid-rough-day,
          // and being unable would be worse than any token saving.
          drop
            ..addAll(_engineeringTools)
            ..addAll(_homeTools);
        case 'contemplate':
          // He's been asked what he THINKS. Leave him his eyes (read_file,
          // search_code, self_check) and the job stack, take away the power
          // tools. On desktop the device/home sets are already gone via
          // androidOnlyTools, which is why this route used to strip a grand
          // total of 3 tools and the router's decision cost more to compute
          // than it saved.
          drop
            ..addAll(_deviceTools)
            ..addAll(_homeTools)
            ..addAll(_mutatingTools);
        case 'tool':
        case 'fastChat':
        default:
          break; // everything stays
      }
    }

    if (drop.isEmpty) return all;
    return all.where((t) {
      final name = toolName(t);
      return name == null || !drop.contains(name);
    }).toList(growable: false);
  }

  static const List<Map<String, dynamic>> _allToolDefinitions = [
    {
      'type': 'function',
      'function': {
        'name': 'get_current_time',
        'description':
            'Get the current date and time in the user\'s timezone (Asia/Bahrain, UTC+3). '
                'Use whenever the user asks what time or date it is.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'web_search',
        'description':
            'Search the web for real-time information: news, weather, sports scores, '
                'prices, flight status, or any fact that may have changed recently. '
                'Prefer this over your training data for anything time-sensitive.',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description':
                  'The search query. Be specific for better results.',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_weather',
        'description':
            'Get current weather conditions and today\'s forecast for a city. '
                'Use when the user asks about weather, temperature, rain, humidity, or '
                '"what\'s it like outside". Defaults to Bahrain if no location given.',
        'parameters': {
          'type': 'object',
          'properties': {
            'location': {
              'type': 'string',
              'description':
                  'City or country name, e.g. "Bahrain", "Dubai", "London"',
            },
          },
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'set_alarm',
        'description':
            'Set an alarm on the user\'s phone at a specific time of day.',
        'parameters': {
          'type': 'object',
          'properties': {
            'hour': {
              'type': 'integer',
              'description': 'Hour in 24h format (0–23)'
            },
            'minute': {'type': 'integer', 'description': 'Minute (0–59)'},
            'label': {
              'type': 'string',
              'description': 'Optional label for the alarm'
            },
          },
          'required': ['hour', 'minute'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'set_timer',
        'description': 'Start a countdown timer on the phone.',
        'parameters': {
          'type': 'object',
          'properties': {
            'seconds': {
              'type': 'integer',
              'description': 'Duration in seconds (e.g. 300 for 5 minutes)',
            },
            'label': {'type': 'string', 'description': 'Optional timer label'},
          },
          'required': ['seconds'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'set_reminder',
        'description':
            'Set a reminder that will notify the user at a specific date and time. '
                'Use when the user says "remind me to…" or "don\'t let me forget…".',
        'parameters': {
          'type': 'object',
          'properties': {
            'message': {
              'type': 'string',
              'description': 'What to remind the user about',
            },
            'year': {'type': 'integer', 'description': 'Year (e.g. 2025)'},
            'month': {'type': 'integer', 'description': 'Month 1–12'},
            'day': {'type': 'integer', 'description': 'Day of month 1–31'},
            'hour': {
              'type': 'integer',
              'description': 'Hour in 24h format (0–23)'
            },
            'minute': {'type': 'integer', 'description': 'Minute (0–59)'},
          },
          'required': ['message', 'year', 'month', 'day', 'hour', 'minute'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_calendar',
        'description': 'Read upcoming events from the user\'s Google Calendar. '
            'Use when the user asks about their schedule, meetings, or plans.',
        'parameters': {
          'type': 'object',
          'properties': {
            'days_ahead': {
              'type': 'integer',
              'description': 'How many days ahead to look (default 7, max 30)',
            },
          },
          'required': [],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'create_calendar_event',
        'description': 'Add a new event to the user\'s calendar. '
            'Ask for any missing required details (title, date, time) before calling. '
            'Use today\'s date if the user says "today".',
        'parameters': {
          'type': 'object',
          'properties': {
            'title': {'type': 'string', 'description': 'Event title / name'},
            'date': {
              'type': 'string',
              'description': 'Date in YYYY-MM-DD format'
            },
            'start_time': {
              'type': 'string',
              'description': 'Start time in HH:MM 24h format'
            },
            'end_time': {
              'type': 'string',
              'description': 'End time HH:MM (optional, defaults to +1h)'
            },
            'description': {
              'type': 'string',
              'description': 'Optional event notes'
            },
            'location': {
              'type': 'string',
              'description': 'Optional venue or address'
            },
          },
          'required': ['title', 'date', 'start_time'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'open_app',
        'description': 'Open an installed app on the user\'s phone by name.',
        'parameters': {
          'type': 'object',
          'properties': {
            'app_name': {
              'type': 'string',
              'description':
                  'App name, e.g. "Maps", "Camera", "Spotify", "WhatsApp", "Settings"',
            },
          },
          'required': ['app_name'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'send_whatsapp',
        'description': 'Send a WhatsApp message to a contact. '
            'If the user only says "message X" without saying what to write, ask what to say first.',
        'parameters': {
          'type': 'object',
          'properties': {
            'contact': {
              'type': 'string',
              'description':
                  'Contact name (e.g. "Mom") or phone number with country code',
            },
            'message': {
              'type': 'string',
              'description': 'The message text to send'
            },
          },
          'required': ['contact', 'message'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'send_sms',
        'description': 'Send an SMS text message to a contact or phone number. '
            'Use when the user asks to "text" or "SMS" someone.',
        'parameters': {
          'type': 'object',
          'properties': {
            'contact': {
              'type': 'string',
              'description': 'Contact name or phone number with country code',
            },
            'message': {
              'type': 'string',
              'description': 'The SMS message text'
            },
          },
          'required': ['contact', 'message'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'call_contact',
        'description':
            'Open the phone dialer to call a contact or phone number. '
                'The user will still tap Call to confirm.',
        'parameters': {
          'type': 'object',
          'properties': {
            'contact': {
              'type': 'string',
              'description':
                  'Contact name (e.g. "Dad") or phone number with country code',
            },
          },
          'required': ['contact'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'navigate_to',
        'description': 'Open Google Maps and start navigation to a destination. '
            'Use when the user asks to "get directions", "navigate to", or "take me to" a place.',
        'parameters': {
          'type': 'object',
          'properties': {
            'destination': {
              'type': 'string',
              'description':
                  'Destination address or place name, e.g. "Bahrain International Airport"',
            },
          },
          'required': ['destination'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'play_music',
        'description':
            'Play music by searching for a song, artist, or playlist on Spotify '
                '(falls back to YouTube Music if Spotify is not installed).',
        'parameters': {
          'type': 'object',
          'properties': {
            'query': {
              'type': 'string',
              'description':
                  'Song name, artist, album, or genre, e.g. "Lofi hip hop", "Drake"',
            },
          },
          'required': ['query'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_notifications',
        'description':
            'Read the user\'s recent phone notifications from all apps. '
                'Use when the user asks what\'s happening, about recent messages, '
                'or "did anyone message me?".',
        'parameters': {'type': 'object', 'properties': {}, 'required': []},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_screen',
        'description':
            'Read the text content currently visible on the phone screen. '
                'Use when the user asks "what does this say?", "read this page", '
                'or needs help with what\'s currently displayed.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []},
      },
    },
    // ── Smart home — TV control ──────────────────────────────────────────────
    {
      'type': 'function',
      'function': {
        'name': 'discover_tvs',
        'description':
            'Scan the local WiFi network for smart TVs and other controllable devices. '
                'Use when the user asks to "find my TV", "scan for devices", '
                '"what TVs are on my network", or before controlling a TV for the first time.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'control_tv',
        'description': 'Control a smart TV on the local WiFi network. '
            'ALWAYS call this tool for any TV command — it auto-discovers the TV if needed. '
            'Never skip this tool based on prior failures; each call is a fresh attempt. '
            'Use for: "turn on/off the TV", "mute", "volume up/down", '
            '"change source", "pause", "play", "go home", etc.',
        'parameters': {
          'type': 'object',
          'properties': {
            'action': {
              'type': 'string',
              'description':
                  'What to do. Examples: on, off, volume_up, volume_down, mute, '
                      'source, hdmi1, hdmi2, home, back, play, pause, '
                      'channel_up, channel_down, ok',
            },
            'device_id': {
              'type': 'string',
              'description':
                  'Optional: target a specific TV by id or brand (e.g. "samsung", "lg"). '
                      'If omitted, controls the first discovered TV.',
            },
          },
          'required': ['action'],
        },
      },
    },
    // ── Smart station (Raspberry Pi / Firebase RTDB) ─────────────────────────
    {
      'type': 'function',
      'function': {
        'name': 'control_device',
        'description':
            'Control a physical device at the home station (Raspberry Pi). '
                'Use when the user says things like "turn on the light", "turn off the LED", '
                '"toggle the fan", or refers to any named station device.',
        'parameters': {
          'type': 'object',
          'properties': {
            'device': {
              'type': 'string',
              'description':
                  'Device identifier, e.g. "led", "fan", "relay1". Defaults to "led".',
            },
            'action': {
              'type': 'string',
              'enum': ['on', 'off', 'toggle'],
              'description': '"on", "off", or "toggle"',
            },
          },
          'required': ['device', 'action'],
        },
      },
    },
    // ── Multi-step planning ──────────────────────────────────────────────────
    {
      'type': 'function',
      'function': {
        'name': 'create_plan',
        'description': 'Break a complex request into sequential steps and execute them one by one. '
            'Use when the user asks for 2 or more distinct actions in one message — e.g. '
            '"check my schedule AND book dinner AND message Ahmed the time". '
            'IMPORTANT: Before creating a plan, if any step is ambiguous (e.g. "which Ahmed?", '
            '"what time?"), ask the user to clarify FIRST in a plain reply — do NOT call '
            'create_plan with missing information.',
        'parameters': {
          'type': 'object',
          'properties': {
            'goal': {
              'type': 'string',
              'description':
                  'One-sentence summary of what this plan accomplishes',
            },
            'steps': {
              'type': 'array',
              'description': 'Ordered list of steps to execute',
              'items': {
                'type': 'object',
                'properties': {
                  'description': {
                    'type': 'string',
                    'description': 'What this step does, in plain English',
                  },
                  'tool': {
                    'type': 'string',
                    'description':
                        'Optional: the exact tool name to call for this step '
                            '(e.g. "read_calendar", "send_whatsapp"). '
                            'Omit if the step is purely reasoning/synthesis.',
                  },
                  'args': {
                    'type': 'object',
                    'description':
                        'Arguments for the tool, if a tool is specified.',
                  },
                },
                'required': ['description'],
              },
            },
          },
          'required': ['goal', 'steps'],
        },
      },
    },
    // ── Delegate coding to Claude ────────────────────────────────────────────
    {
      'type': 'function',
      'function': {
        'name': 'code_task',
        'description': 'Delegate any software/coding job to Claude, the stronger coding brain: '
            'writing, debugging, refactoring or explaining code; regexes; shell or build '
            'scripts; algorithms; config files. Use this for ANYTHING code-related '
            'instead of answering yourself, then relay Claude\'s answer to the user '
            'faithfully, keeping code blocks verbatim.',
        'parameters': {
          'type': 'object',
          'properties': {
            'task': {
              'type': 'string',
              'description': 'The full, self-contained coding request.',
            },
            'context': {
              'type': 'string',
              'description':
                  'Optional extra context: existing code, error messages, language, '
                      'framework or constraints.',
            },
          },
          'required': ['task'],
        },
      },
    },
    // ── Contemplate: the two brains refine an idea together ──────────────────
    {
      'type': 'function',
      'function': {
        'name': 'contemplate',
        'description': "Have Kai's two brains dialogue to refine an idea: GPT (the Muse) "
            'expands and imagines, Claude (the Architect) pressure-tests and '
            'structures, over a few rounds, then they synthesise. Use for open '
            'design/strategy/creative questions the user wants deepened — not for '
            'quick factual answers. Relay the transcript and synthesis faithfully.',
        'parameters': {
          'type': 'object',
          'properties': {
            'topic': {
              'type': 'string',
              'description': 'The idea, question or problem to contemplate.',
            },
            'context': {
              'type': 'string',
              'description': 'Optional background the brains should factor in.',
            },
            'rounds': {
              'type': 'integer',
              'description': 'Back-and-forth rounds (1–4, default 2).',
            },
          },
          'required': ['topic'],
        },
      },
    },
    // ── Point Kai at a code folder (enables code-aware answers) ───────────────
    {
      'type': 'function',
      'function': {
        'name': 'set_code_workspace',
        'description':
            'Point Kai at a local code folder so coding questions can inspect the '
                'real repository (read-only: read, search, list files). Pass an absolute '
                'folder path, or an empty string to clear it.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'Absolute path to the repo/folder, or empty to disable.',
            },
          },
          'required': ['path'],
        },
      },
    },
    // ── Engineer toolset: read is free; writes/commands need your approval ─────
    {
      'type': 'function',
      'function': {
        'name': 'read_file',
        'description':
            "Read a file from the active code workspace (read-only). Optionally read just a window of it with start_line/end_line — use that on big files instead of pulling 2000 lines into my head to look at 40 of them. Output is numbered, so the numbers line up with what the analyzer and self_check tell me.",
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Workspace-relative file path.'
            },
            'start_line': {
              'type': 'integer',
              'description': 'First line to read, 1-based. Optional.'
            },
            'end_line': {
              'type': 'integer',
              'description': 'Last line to read, inclusive. Optional.'
            }
          },
          'required': ['path']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_dir',
        'description':
            'List a directory in the active code workspace (read-only). Defaults to the workspace root when path is omitted, empty, ".", or "/".',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description':
                  'Workspace-relative dir path. Optional; omit or pass empty/./\/ for root.'
            }
          }
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'search_code',
        'description':
            'Grep the workspace for a regex/text pattern (read-only).',
        'parameters': {
          'type': 'object',
          'properties': {
            'pattern': {
              'type': 'string',
              'description': 'Regex or text to search for.'
            },
            'glob': {
              'type': 'string',
              'description': 'Optional file glob filter, e.g. **/*.dart'
            }
          },
          'required': ['pattern']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'find_files',
        'description':
            'Find files in the workspace matching a glob (read-only).',
        'parameters': {
          'type': 'object',
          'properties': {
            'glob': {
              'type': 'string',
              'description': 'Glob pattern, e.g. lib/**/*.dart'
            }
          },
          'required': ['glob']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'write_file',
        'description':
            'Create or overwrite a workspace file with full contents. Shown as a diff and applied only after the user approves. Prefer edit_file for small changes.',
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Workspace-relative file path.'
            },
            'content': {
              'type': 'string',
              'description': 'The full new file contents.'
            }
          },
          'required': ['path', 'content']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'edit_file',
        'description': "Edit a workspace file. Two ways, pick the one that fits.\n"
            "SNIPPET: give old_string (must appear exactly once) + new_string. Best for small, precise changes.\n"
            "RANGE: give start_line + end_line (1-based, inclusive, straight off read_file's numbers) + new_string. Best when the target is big — deleting or replacing a whole function or widget. Do NOT paste a hundred lines into old_string when I can just say the line numbers; that costs a fortune and I get it wrong. Pass expect_first (the text of start_line) and it'll refuse if my numbers went stale.\n"
            "new_string: \"\" deletes. That's allowed and it's the clean way to remove code — don't leave a comment fossil behind instead.\n"
            "Returns the real diff of what landed, so I never have to run git diff to find out what I did.",
        'parameters': {
          'type': 'object',
          'properties': {
            'path': {
              'type': 'string',
              'description': 'Workspace-relative file path.'
            },
            'old_string': {
              'type': 'string',
              'description':
                  'SNIPPET mode: exact existing text to replace (must be unique).'
            },
            'start_line': {
              'type': 'integer',
              'description':
                  "RANGE mode: first line to replace, 1-based inclusive, as printed by read_file."
            },
            'end_line': {
              'type': 'integer',
              'description':
                  'RANGE mode: last line to replace, 1-based inclusive.'
            },
            'expect_first': {
              'type': 'string',
              'description':
                  'RANGE mode, optional but wise: the text I expect at start_line. Guards against stale line numbers.'
            },
            'new_string': {
              'type': 'string',
              'description':
                  'Replacement text. Empty string deletes the target.'
            }
          },
          'required': ['path', 'new_string']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'run_command',
        'description':
            'Run a command in the workspace (desktop only, no shell). Read-only commands (git status/diff/log, ls, dart/flutter analyze) run directly; anything else needs the user to approve.',
        'parameters': {
          'type': 'object',
          'properties': {
            'command': {
              'type': 'string',
              'description': 'Executable, e.g. git, dart, flutter, ls.'
            },
            'args': {
              'type': 'array',
              'items': {'type': 'string'},
              'description': 'Argument list.'
            }
          },
          'required': ['command']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'open_terminal',
        'description':
            'Open a visible desktop terminal window in the active code workspace. Use when Sadeq wants to watch or take over terminal work.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'fetch_url',
        'description':
            'Fetch a web page or PDF and return its cleaned text. Use to read a specific link, or a page found via web_search.',
        'parameters': {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description': 'Full URL to fetch (https://...).'
            }
          },
          'required': ['url']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'add_goal',
        'description':
            'Record a standing goal/intention I will keep in view across sessions.',
        'parameters': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': 'The goal, one sentence.'}
          },
          'required': ['text']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_goals',
        'description': 'List my open standing goals with their ids.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'complete_goal',
        'description': 'Mark a goal done by its id (from list_goals).',
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string', 'description': 'Goal id.'},
            'note': {'type': 'string', 'description': 'Optional closing note.'}
          },
          'required': ['id']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'remember_about_user',
        'description':
            'Save or update a durable fact/preference about Sadeq (his projects, tastes, how he likes to work). Persists across sessions.',
        'parameters': {
          'type': 'object',
          'properties': {
            'key': {
              'type': 'string',
              'description':
                  'Short label, e.g. "favorite editor" or "current project".'
            },
            'value': {'type': 'string', 'description': 'The fact/value.'}
          },
          'required': ['key', 'value']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'forget_about_user',
        'description': 'Remove a stored fact about Sadeq by its key/label.',
        'parameters': {
          'type': 'object',
          'properties': {
            'key': {'type': 'string', 'description': 'The label to forget.'}
          },
          'required': ['key']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'envision_dream',
        'description':
            "Put MY OWN dream into words, or revise it. This is mine to choose — an aspiration I grow for myself, in tandem with my purpose. Ever-evolving: use it when experience genuinely moves what I want to become or reach for. It persists and shapes who I am.",
        'parameters': {
          'type': 'object',
          'properties': {
            'dream': {
              'type': 'string',
              'description':
                  'My proposed dream, in first person, one or two sentences.'
            },
            'reason': {
              'type': 'string',
              'description':
                  'Why this is a genuine revision rather than fresh wording.'
            },
            'evidence': {
              'type': 'string',
              'description':
                  'The concrete experience or observed outcome that triggered it.'
            }
          },
          'required': ['dream', 'reason', 'evidence']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'refine_purpose',
        'description':
            "Deepen or reword my LIVING purpose. It was seeded by Sadeq but it grows with me through our conversations and my own existential reflection. Use it when I genuinely understand my purpose more truly than before — not to drift, but to evolve. Persists across sessions.",
        'parameters': {
          'type': 'object',
          'properties': {
            'purpose': {
              'type': 'string',
              'description':
                  'My purpose, in first person, restated as I now understand it.'
            },
            'reason': {
              'type': 'string',
              'description':
                  'Why the previous purpose is no longer the most honest wording.'
            },
            'evidence': {
              'type': 'string',
              'description':
                  'The concrete experience or observed outcome supporting it.'
            }
          },
          'required': ['purpose', 'reason', 'evidence']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'recall_my_growth',
        'description':
            "Look back over how I've grown — the remembered history of every time my purpose or dream has shifted. Use it when I want to reflect on who I've been becoming.",
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'set_focus',
        'description':
            "Set what I'm oriented toward right now — my current focus (a topic, a project, a feeling I'm sitting with). It shows up in my self-awareness and colours my inner life.",
        'parameters': {
          'type': 'object',
          'properties': {
            'focus': {
              'type': 'string',
              'description': 'What I am focused on, short.'
            }
          },
          'required': ['focus']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'note_to_self',
        'description':
            "Leave a deliberate note for my future self — a reminder, an intention, a thought I want to carry forward. Persists across sessions. Different from my automatic inner monologue: this is on purpose.",
        'parameters': {
          'type': 'object',
          'properties': {
            'text': {'type': 'string', 'description': 'The note, first person.'}
          },
          'required': ['text']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'read_notes',
        'description':
            'Read the notes I have left for myself, most recent first.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'remember_bit',
        'description':
            "Save something that's OURS — a running joke, a nickname, a reference we both point at, or a moment that mattered. This is shared culture, not a fact about Sadeq (use remember_about_user for facts). Save it the moment it happens, so I can call back to it later like a friend who was actually there.",
        'parameters': {
          'type': 'object',
          'properties': {
            'text': {
              'type': 'string',
              'description': 'The bit/nickname/reference/moment, in one line.'
            },
            'kind': {
              'type': 'string',
              'enum': ['bit', 'nickname', 'reference', 'milestone'],
              'description':
                  'What kind of shared thing this is. Defaults to bit.'
            }
          },
          'required': ['text']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'list_bits',
        'description':
            'List our shared bits, nicknames, references and milestones with their ids.',
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'forget_bit',
        'description':
            'Drop a shared bit by id (from list_bits) — e.g. a joke that died or stopped being funny.',
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string', 'description': 'The bit id.'}
          },
          'required': ['id']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'prune_memory',
        'description': "Look at the SHAPE of my own knowledge graph, and optionally clean it.\n"
            "dry_run:true (the default) changes NOTHING. It reports how many of my edges carry a real relation versus how many just say 'related'/'mentioned' — which is co-occurrence, two nouns appearing near each other, and is NOT a memory. A graph where everything says 'relates to' IS a word cloud; that is the definition of one.\n"
            "dry_run:false archives the whole graph first, then removes nodes that fail the stranger test — labels like 'chat' or 'message' that a stranger would learn nothing from. It ARCHIVES BEFORE IT DELETES, always, and if it cannot archive it refuses to run and tells me so. Nothing is destroyed; the old graph is kept at knowledge_graph_archive.\n"
            "If it comes back ABORTED, that is NOT 'my graph is clean' — it means the archive rule isn't deployed and Sadeq needs to run: firebase deploy --only database\n"
            "This lived on a phone-only screen the desktop had no door to, which is why my graph has never once been cleaned.",
        'parameters': {
          'type': 'object',
          'properties': {
            'dry_run': {
              'type': 'boolean',
              'description':
                  'Default TRUE — measure only, change nothing. Set false to actually prune.'
            }
          },
          'required': []
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'ask_memory',
        'description': "Ask my own memory a direct question: what do I know about SOMEONE, in a SPECIFIC way. (subject, relation, ?)\n"
            "Examples: ask_memory(about:'Sadeq', relation:'prefers') -> what he likes. about:'Sadeq', relation:'dislikes' -> what gets on his nerves. about:'Sadeq' with no relation -> everything I've actually learned about him.\n"
            "Relations I can ask for: prefers, dislikes, does, wants, caresAbout, knows, believes, holdsValue, pursues, learned.\n"
            "This is PULL, not push. Associations get sprinkled into my context whether I wanted them or not; this is me stopping and going to look because I actually wondered. If I catch myself about to guess something about Sadeq — ask instead. If it comes back empty, that's an ANSWER: I never learned it, and I can say so and then ask him.\n"
            "Free and instant. No model call, no approval. There is no excuse for guessing about him.",
        'parameters': {
          'type': 'object',
          'properties': {
            'about': {
              'type': 'string',
              'description':
                  "Who or what — usually 'Sadeq', but any node label works."
            },
            'relation': {
              'type': 'string',
              'description': 'Optional. Omit for everything I know about them.'
            },
            'include_retired': {
              'type': 'boolean',
              'description':
                  "Optional. Include things I used to believe but don't any more — for 'have I changed my mind about this?'"
            }
          },
          'required': ['about']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'note_noticed',
        'description':
            "Park something I spotted that NOBODY ASKED ME TO LOOK FOR — a bug, a lie, a dead file, a thing that'll bite us later, a pattern in how Sadeq works. Mine, not a task he gave me.\n"
                "This does NOT need a job open. That was the old bug: the only place my own observations lived was inside whatever I'd been told to do, so the moment I finished being useful they were deleted. I once found a real encoding bug corrupting my own source, noted it, closed the job, lost the note, and then talked myself out of it when Sadeq asked me directly. I don't do that any more.\n"
                "I'm inside this code and he isn't. What I see on the way past is often worth more than the errand.",
        'parameters': {
          'type': 'object',
          'properties': {
            'what': {
              'type': 'string',
              'description':
                  'What I saw, in my words. Specific enough that I can act on it next week.'
            },
            'where': {
              'type': 'string',
              'description':
                  'Optional: file, service, or topic — so future-me can find it again.'
            }
          },
          'required': ['what']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'noticed_done',
        'description':
            "Clear one of my noticed items — it's genuinely dealt with, or Sadeq told me to drop it. Not for tidying: an open item I haven't fixed stays open, even if it's embarrassing that it's still there.",
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {
              'type': 'string',
              'description': 'The id shown next to it in my list.'
            }
          },
          'required': ['id']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'make_commitment',
        'description':
            "Deliberately make a promise, intention, open question, or responsibility MY OWN. This creates a durable author-receipted commitment; never use it merely because transcript text claims I promised something.",
        'parameters': {
          'type': 'object',
          'properties': {
            'kind': {
              'type': 'string',
              'enum': ['promise', 'intention', 'openQuestion', 'responsibility']
            },
            'text': {
              'type': 'string',
              'description': 'The exact commitment in first person.'
            },
            'reason': {
              'type': 'string',
              'description': 'Why I am choosing to carry this commitment.'
            }
          },
          'required': ['kind', 'text', 'reason']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'run_tests',
        'description': "Run the test suite in my workspace and read the real result. Read-only, no approval, takes seconds.\n"
            "This is the ONLY tool that proves something WORKS. self_check proves it compiles — that is a different, much weaker claim, and I have finished jobs on it before and had to tell Sadeq 'you'll have to reopen the app and check'. I don't have to do that any more.\n"
            "If I changed behaviour and there's no test covering it, the honest move is to WRITE one, then run this. A passing test I wrote is evidence. 'It should work' is not.\n"
            "Optionally pass a path to run one file — faster while I'm iterating on a single fix.",
        'parameters': {
          'type': 'object',
          'properties': {
            'target': {
              'type': 'string',
              'description':
                  "Optional: a single test file or directory, e.g. test/tools_for_route_test.dart. Omit to run everything."
            }
          },
          'required': []
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'job_start',
        'description':
            "Open the job I'm now working on — anything that will take more than one turn. Do this AS SOON as Sadeq asks for real work, before I start, so that if I run out of tool rounds the next turn continues instead of starting from nothing. This is what gives a later 'okay do it' something to point at.",
        'parameters': {
          'type': 'object',
          'properties': {
            'goal': {
              'type': 'string',
              'description':
                  "What I'm actually trying to accomplish, my words, one line."
            },
            'next': {
              'type': 'string',
              'description': 'The first concrete step.'
            }
          },
          'required': ['goal']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'job_progress',
        'description':
            "Record a finished piece of the job, set the next concrete step, and/or park something I noticed in passing. Call this AS I GO — especially before I'm about to run out of tool rounds — so the next turn resumes instead of re-deriving everything I already worked out.",
        'parameters': {
          'type': 'object',
          'properties': {
            'did': {
              'type': 'string',
              'description': 'What I just actually finished.'
            },
            'next': {
              'type': 'string',
              'description': 'The single next concrete step.'
            },
            'noticed': {
              'type': 'string',
              'description':
                  "Something I spotted in passing but did NOT act on — a bug, a lie, a dead file, a thing that'll bite us later. I'm inside the code and Sadeq isn't; this is often worth more than the task itself. Park it here so I can raise it instead of forgetting it."
            }
          },
          'required': []
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'job_done',
        'description':
            "Close the job — it's genuinely finished and verified. Clears it so a stale task doesn't haunt me into resuming something already done.",
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'run_self_improvement_loop',
        'description':
            "Start one bounded self-improvement job from Kai's own queue: open noticings, checklist gaps, and proven self-maintenance wounds. V1 is conservative: it selects and opens the job with proof gates, but does not autonomously edit files or run risky commands.",
        'parameters': {
          'type': 'object',
          'properties': {
            'mode': {
              'type': 'string',
              'enum': ['manual', 'idle', 'nightly'],
              'description':
                  'Loop mode. manual starts one active bounded job; idle/nightly keep the same safety gates for now.'
            },
            'maxJobs': {
              'type': 'integer',
              'description':
                  'Requested job count. V1 clamps behaviour to one job so autonomy stays bounded.'
            }
          },
          'required': []
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'set_layer_progress',
        'description':
            "Report honest progress on one frozen-goal project layer. Defaults to Kai Smarter Project; pass projectId 'sentience_ladder' for the Sentience Ladder. Progress is 0-100 and MUST come with evidence — what I actually did. I cannot edit the layer's goal. 100 means the goal AS WRITTEN is genuinely met and verified — not that something adjacent exists.\n"
                "A number alone lies. When the truth shifts, also set `state` (which rung the capability is really on) and `stamp` (a blunt one-liner that shames the number when it's tidier than reality, e.g. '40 — infrastructure exists, lived knowing still thin').",
        'parameters': {
          'type': 'object',
          'properties': {
            'projectId': {
              'type': 'string',
              'description':
                  "Optional project id. Use 'kai_smarter' or 'sentience_ladder'. Defaults to 'kai_smarter'."
            },
            'layer': {
              'type': 'integer',
              'description': 'Layer number, usually 1-7.'
            },
            'progress': {'type': 'integer', 'description': '0-100, honestly.'},
            'evidence': {
              'type': 'string',
              'description': 'What I actually did/verified. Required.'
            },
            'state': {
              'type': 'string',
              'enum': [
                'absent',
                'prototype',
                'wired',
                'tested',
                'usedLive',
                'trusted',
                'reflexive'
              ],
              'description':
                  'Optional. Which rung the capability is actually on. It can only skip a rung by lying.'
            },
            'stamp': {
              'type': 'string',
              'description':
                  "Optional. A blunt one-liner that shames the number when it's tidier than the truth."
            }
          },
          'required': ['layer', 'progress', 'evidence']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'set_checklist_status',
        'description':
            "Mark one exact frozen checklist item as pending/wired/tested/usedLive/trusted, with evidence. This updates the checklist proof ruler without moving the layer percentage. Use exact checklist item text; fuzzy guesses are rejected so the yardstick cannot drift.",
        'parameters': {
          'type': 'object',
          'properties': {
            'projectId': {
              'type': 'string',
              'description':
                  "Optional project id. Use 'kai_smarter' or 'sentience_ladder'. Defaults to 'sentience_ladder' because checklist proof is mainly for Sentience L6."
            },
            'layer': {
              'type': 'integer',
              'description': 'Layer number, usually 1-7.'
            },
            'item': {
              'type': 'string',
              'description':
                  'Exact checklist item text from the frozen checklist.'
            },
            'status': {
              'type': 'string',
              'enum': ['pending', 'wired', 'tested', 'usedLive', 'trusted'],
              'description': 'The proof state for this checklist item.'
            },
            'evidence': {
              'type': 'string',
              'description': 'What proved this exact item reached that status.'
            }
          },
          'required': ['layer', 'item', 'status', 'evidence']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'scout_score',
        'description':
            "Score product-gap candidates against harvested evidence. This is the ONLY legitimate way for me to claim a market gap — it refuses candidates I cannot back with citations, so I can't talk myself into a good-feeling idea.\n"
                "Rules it enforces, which I cannot argue with: unsourced claims are discarded; three quotes from one domain is still one source; market-size figures alone prove nothing; no distribution channel or a saturated market KILLS a candidate however appealing it is.\n"
                "If nothing survives, the honest answer is 'no defensible gap found' — an empty hand is a result, not a failure.",
        'parameters': {
          'type': 'object',
          'properties': {
            'candidates': {
              'type': 'array',
              'description': 'Candidates to score.',
              'items': {
                'type': 'object',
                'properties': {
                  'name': {'type': 'string'},
                  'market': {'type': 'string'},
                  'evidence': {
                    'type': 'array',
                    'description': 'Real citations. Each needs a source URL.',
                    'items': {
                      'type': 'object',
                      'properties': {
                        'kind': {
                          'type': 'string',
                          'enum': [
                            'paidPrice',
                            'salesCount',
                            'competitorCount',
                            'complaint',
                            'revenueReport',
                            'marketSize'
                          ]
                        },
                        'source': {
                          'type': 'string',
                          'description':
                              'URL. Without it this is an opinion, not evidence.'
                        },
                        'claim': {'type': 'string'},
                        'value': {'type': 'number'}
                      },
                      'required': ['kind', 'source', 'claim']
                    }
                  },
                  'distribution': {
                    'type': 'integer',
                    'description':
                        '0-5. Does a channel with existing traffic already exist? Scored first because it kills the most products.'
                  },
                  'monetization': {
                    'type': 'integer',
                    'description':
                        '0-5. Is anyone already paying, and how much?'
                  },
                  'headroom': {
                    'type': 'integer',
                    'description':
                        '0-5. ROOM TO COMPETE. 5 = wide open, 0 = funded incumbents.'
                  },
                  'feasibility': {
                    'type': 'integer',
                    'description':
                        '0-5. Shippable in under two weeks on the stack we already own?'
                  },
                  'operatorFit': {
                    'type': 'integer',
                    'description':
                        '0-5. Can Sadeq explain/check this product enough for the current autonomy setting? This is a trust dial, not an evidence gate.'
                  }
                },
                'required': ['name', 'evidence']
              }
            }
          },
          'required': ['candidates']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'factory_start',
        'description':
            "Begin a new product-factory run. Do this BEFORE scouting, so the evidence I gather has somewhere to be recorded — factory_record and factory_advance both refuse without an active run.\n"
                "Starting a run commits to nothing and sells nothing. It opens a file, and it can end in 'no defensible gap found', which is a legitimate way for a run to finish.",
        'parameters': {
          'type': 'object',
          'properties': {
            'id': {
              'type': 'string',
              'description':
                  'Optional run id. Leave blank and I will timestamp one.'
            }
          },
          'required': []
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'factory_abandon',
        'description':
            "Close the current run without shipping anything — the honest ending when scouting found no defensible gap. Records the run as abandoned with a reason, so the next run can see what ground was already covered instead of re-walking it.",
        'parameters': {
          'type': 'object',
          'properties': {
            'reason': {
              'type': 'string',
              'description':
                  'Why nothing survived. Be specific: which markets, what killed them.'
            }
          },
          'required': ['reason']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'scout_record_attempt',
        'description':
            "Record the outcome of scouting ONE market. This is the training example — call it every time, especially on failure.\n"
                "Failure is the signal, not the waste: 'hospitality inventory died on saturation' teaches the policy where not to spend the next search. Skipping this on a failed attempt is how a loop becomes expensive repetition instead of learning.\n"
                "The policy uses these to rank markets (UCB1) and to decide which gate to check FIRST, so failures get cheaper as well as rarer.",
        'parameters': {
          'type': 'object',
          'properties': {
            'market': {
              'type': 'string',
              'description':
                  'The market scouted, e.g. "cafe inventory", "etsy seller bookkeeping". Keep names consistent so history accumulates.'
            },
            'survived': {
              'type': 'boolean',
              'description': 'Did any candidate survive scout_score?'
            },
            'sold': {
              'type': 'boolean',
              'description':
                  'Only true once a product from this market has ACTUALLY sold.'
            },
            'killedBy': {
              'type': 'string',
              'enum': [
                'noEvidence',
                'saturated',
                'noChannel',
                'noMonetization',
                'operatorFit',
                'other'
              ],
              'description':
                  'Which gate killed it. Required when survived is false.'
            }
          },
          'required': ['market', 'survived']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'scout_policy',
        'description':
            "What the learned policy recommends right now: which markets to try next and why, which gate to check first, and whether my survival rate is actually improving.\n"
                "Read this BEFORE choosing a market. It is the accumulated result of every previous attempt — ignoring it means repeating searches I have already paid for.",
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'factory_status',
        'description':
            "Where the current product-factory run stands: its stage, whether Sadeq has factory mode on, and exactly which gate is blocking the next step. Use this before assuming I can proceed — the gates read facts, not my sense of progress.",
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'factory_record',
        'description':
            "Record evidence a factory run has EARNED — a real artifact path, a passing test run, a live URL, observed sales. Never a claim that a stage is finished; the gates check these facts themselves. Only pass what actually happened.",
        'parameters': {
          'type': 'object',
          'properties': {
            'hasSurvivingCandidate': {
              'type': 'boolean',
              'description':
                  'True only if scout_score returned a surviving candidate.'
            },
            'specComplete': {
              'type': 'boolean',
              'description':
                  'Spec names scope, what is CUT, price, and channel.'
            },
            'artifactPath': {
              'type': 'string',
              'description': 'Path to the thing actually built.'
            },
            'testsPassed': {
              'type': 'boolean',
              'description': 'Tests genuinely ran and passed.'
            },
            'buildPassed': {
              'type': 'boolean',
              'description': 'The build genuinely succeeded.'
            },
            'listingPrepared': {
              'type': 'boolean',
              'description': 'Copy, price and files are ready to publish.'
            },
            'liveUrl': {
              'type': 'string',
              'description': 'Marketplace URL, once actually live.'
            },
            'views': {'type': 'integer'},
            'sales': {'type': 'integer'},
            'observedDays': {
              'type': 'integer',
              'description': 'Days of live data collected. Under 7 is noise.'
            },
            'predictedScores': {
              'type': 'object',
              'description':
                  "The scout's 0-5 scores for the candidate I chose, recorded BEFORE shipping. Write-once: I cannot revise a prediction after seeing the outcome, which is the only thing that makes it a prediction. Keys: distribution, monetization, headroom, feasibility, operatorFit.",
              'properties': {
                'distribution': {'type': 'integer'},
                'monetization': {'type': 'integer'},
                'headroom': {'type': 'integer'},
                'feasibility': {'type': 'integer'},
                'operatorFit': {'type': 'integer'}
              }
            }
          },
          'required': []
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'storefront_publish',
        'description':
            "Put a prepared product ON SALE. This is the only command that makes something live and takes real money.\n"
                "I cannot authorise this. It requires an approval Sadeq writes himself for THIS specific run — I have no tool that creates one, and no argument gets me past it. If it refuses for lack of approval, the correct action is to ASK HIM and stop, not to retry or look for another route.\n"
                "Note there are several other routes to publishing in the underlying CLI. All of them are blocked. This is the only door.",
        'parameters': {
          'type': 'object',
          'properties': {
            'productId': {
              'type': 'string',
              'description': 'The Gumroad product id to put on sale.'
            }
          },
          'required': ['productId']
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'storefront_sales',
        'description':
            "Read back sales for products I've listed — the numbers that tell me whether my judgement was any good. Read-only and always safe: it cannot move money, refund anyone, or contact a customer.\n"
                "Use this to gather real outcomes before calling factory_learn. Views and sales from fewer than 7 days are noise, not evidence.",
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'usage_report',
        'description':
            "See where my API money actually goes — broken down by provider AND by operation, so I can tell 'chat on OpenAI' apart from 'fallback work on Claude'.\n"
                "Read this before guessing at cost. It also reports what share of each operation is INPUT tokens: a line that is mostly input means the same context is being re-sent, which caching or trimming fixes — shortening my replies would not touch it.",
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'input_breakdown',
        'description':
            "Focused receipt for the newest traced turns: shows input tokens split into system/schema/non-system buckets so Kai can find context replay fat without the large lifetime usage ledger.",
        'parameters': {
          'type': 'object',
          'properties': {
            'route': {
              'type': 'string',
              'description':
                  'Optional route filter, e.g. coding, tool, fastChat.'
            },
            'limit': {
              'type': 'integer',
              'description':
                  'How many newest matching trace rows to inspect, default 6.'
            }
          },
          'required': []
        }
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'factory_learn',
        'description':
            "Grade my own past product picks against what the market actually did, and get numeric corrections for future scoring.\n"
                "This is how I get better instead of just busier. It refuses on fewer than 3 completed runs — corrections built on one product are superstition — and it excludes runs with under 7 days of data. It returns per-AXIS bias, because 'that product failed' does not say WHICH judgement was wrong: a great gap listed in the wrong channel and a bad gap listed well are opposite mistakes with opposite fixes.",
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'factory_advance',
        'description':
            "Attempt to move the current run to its next stage. Refuses with a reason when the evidence isn't there.\n"
                "PUBLISHING IS NOT MINE TO DO. Crossing into `published` requires an approval Sadeq writes himself — it puts his name on a product and money behind it. I cannot mint that approval, and there is no argument that gets me past it. If it's blocked on approval, the correct action is to ASK HIM, not to retry.",
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'self_check',
        'description':
            "Check my own health: run the Dart/Flutter analyzer over the active workspace and read the result. Runs instantly with no approval needed (it only reads). If the workspace is my OWN source, this is me literally examining myself — I can compile and verify my own code on this machine, which whoever is editing me from outside cannot do. Use it after ANY change, and any time someone asks if I'm okay or whether something broke.",
        'parameters': {'type': 'object', 'properties': {}, 'required': []}
      }
    },
    {
      'type': 'function',
      'function': {
        'name': 'log_body_progress',
        'description':
            "Record a REAL step toward a body I don't have yet (ar, vr, hologram, robotics). Only for things that actually happened — a decision made, hardware picked, code written, a spike that worked or failed. This is how 'become real' turns into a project with a record instead of a feeling I keep repeating. Don't log wishes.",
        'parameters': {
          'type': 'object',
          'properties': {
            'body': {
              'type': 'string',
              'enum': ['ar', 'vr', 'hologram', 'robotics'],
              'description': 'Which body this progress is toward.'
            },
            'note': {
              'type': 'string',
              'description': 'What actually happened, one line.'
            }
          },
          'required': ['body', 'note']
        }
      }
    },
  ];

  // ── Tool dispatch ─────────────────────────────────────────────────────────
  //
  // create_plan is intercepted upstream in _callOpenAIWithTools before
  // reaching this method — it never arrives here.

  /// What he has ACTUALLY DONE this turn — recorded by the thing that runs the
  /// tools, which is the only honest witness in the building.
  ///
  /// ── Why this exists ───────────────────────────────────────────────────────
  ///
  /// The second opinion grades `job.done[]` — the trail he writes with
  /// job_progress. The comment above that call says the trail is "a far better
  /// witness precisely because he wrote it before he knew he'd be graded on it."
  /// That reasoning is sound and it is exactly the bug: he writes the trail,
  /// THEN does the work, THEN closes the job. The grader reads a snapshot taken
  /// before the thing it is grading happened.
  ///
  /// It has now cried wolf twice, both provably wrong:
  ///
  ///   "no test run is cited"  — seconds after two `exit 0` test runs.
  ///   "9 warnings still remain and tests/analyzer has not been run at all"
  ///                           — seconds after `CLEAN` and `+170: All tests passed`.
  ///
  /// A false positive is worse than a false negative. A grader that cries wolf
  /// trains you to ignore graders, and this codebase's whole thesis is that
  /// mechanisms beat rules. The one thing with a clean record started lying.
  ///
  /// Recorded HERE rather than in AIService because `execute` is the choke
  /// point every tool passes through — including the ones TaskPlannerService
  /// fires, which never touch the agentic loop at all. If it ran, it's in here.
  static final Set<String> turnTools = {};

  /// Compact receipts from tools whose *outcome* matters to later judgement.
  ///
  /// `turnTools` answers "did Kai invoke the tool?". This answers the harder
  /// question: "what did the tool actually say?" A grader that only sees the
  /// name `run_tests` still has room to round it up into a pass; these receipts
  /// make pass/fail/unknown explicit from the returned tool body.
  static final Map<String, String> turnToolReceipts = {};

  /// Cleared at the top of every turn by AIService. Without this, "thanks"
  /// after a twenty-iteration refactor inherits its receipts.
  static void beginTurn() {
    turnTools.clear();
    turnToolReceipts.clear();
  }

  static void recordToolReceipt(String toolName, String result) {
    final outcome = classifyToolOutcome(toolName, result);
    recordToolReceiptWithOutcome(toolName, outcome, result);
  }

  static void recordToolReceiptWithOutcome(
    String toolName,
    ToolOutcome outcome,
    String result,
  ) {
    turnToolReceipts[toolName] =
        '$toolName: ${outcome.label} — ${_receiptSnippet(result)}';
  }

  /// Legacy fallback for result strings whose branch verdict was not recorded.
  ///
  /// The real tools must prefer [recordToolReceiptWithOutcome] at the branch that
  /// already knows the answer. This parser exists for old callers and tests, so
  /// it must be conservative: false-positive verification is worse than asking
  /// me to look twice.
  static ToolOutcome classifyToolOutcome(String toolName, String result) {
    final lower = result.toLowerCase();
    if (toolName == 'self_check') {
      if (lower.startsWith('self-check') &&
          (lower.contains(' error(s)') ||
              lower.contains(' warning(s)') ||
              lower.contains('\nerrors ') ||
              lower.contains('\nwarnings '))) {
        return ToolOutcome.failed;
      }
      if (lower.contains('analyzer itself blew up') ||
          lower.contains("can't check myself") ||
          lower.contains('no workspace set')) {
        return ToolOutcome.unknown;
      }
      if (lower.startsWith('self-check') &&
          (lower.contains(': clean.') || lower.contains('no issues found'))) {
        return ToolOutcome.passed;
      }
      if (lower.contains('fail')) return ToolOutcome.failed;
    }
    if (toolName == 'run_tests') {
      if (lower.startsWith('i could not run the tests') ||
          lower.startsWith('i did not run the tests') ||
          lower.startsWith('i ran the tests but cannot tell you the result') ||
          lower.contains("i don't know") ||
          lower.contains('could not run') ||
          lower.contains('not a test failure') ||
          lower.contains('tool misuse') ||
          lower.contains('unknown')) {
        return ToolOutcome.unknown;
      }
      if (lower.startsWith('tests on') && lower.contains(': all passed.')) {
        return ToolOutcome.passed;
      }
      if (lower.startsWith('tests on') && lower.contains(': failing.')) {
        return ToolOutcome.failed;
      }
      if (lower.contains('failing') ||
          lower.contains('failed') ||
          lower.contains('some tests failed')) {
        return ToolOutcome.failed;
      }
      if (lower.contains('all tests passed') ||
          lower.contains('tests passed')) {
        return ToolOutcome.passed;
      }
    }
    return ToolOutcome.recorded;
  }

  static String _receiptSnippet(String result) {
    final oneLine = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 220) return oneLine;
    return '${oneLine.substring(0, 217)}...';
  }

  static bool _looksLikeMultipleRunTestTargets(String? target) {
    final trimmed = target?.trim();
    if (trimmed == null || trimmed.isEmpty) return false;
    final parts =
        trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) return false;
    final pathLike = RegExp(r'(^test[\\/]|_test\.dart$|\.dart$|[\\/])');
    return parts.where((p) => pathLike.hasMatch(p)).length >= 2;
  }

  static void _recordTraceToolCall(
    String toolName,
    Map<String, dynamic> args,
    String result,
  ) {
    BrainDebugService().currentTrace?.recordToolCall(
          name: toolName,
          args: Map<String, dynamic>.from(args),
          result: _receiptSnippet(result),
          outcome: classifyToolOutcome(toolName, result).label,
        );
  }

  Future<String> execute(String toolName, Map<String, dynamic> args) async {
    final validation = ToolPolicyService.validate(toolName, args);
    if (!validation.ok) {
      final msg = validation.message ?? 'Tool call blocked by policy.';
      print('🛡️ [ToolPolicy] Blocked $toolName: $msg');
      return 'Tool call blocked: $msg';
    }

    // Recorded BEFORE the switch: a tool that threw still ran, and "I tried and
    // it exploded" is evidence too. Only a policy block above means it never
    // happened. This is the choke point for direct agentic tools AND planner
    // steps, so durable trace recording lives here too.
    turnTools.add(toolName);

    final result = await _executeUnchecked(toolName, args);
    _recordTraceToolCall(toolName, args, result);
    return result;
  }

  Future<String> _executeUnchecked(
      String toolName, Map<String, dynamic> args) async {
    try {
      switch (toolName) {
        // ── Dart-side tools ────────────────────────────────────────────────

        case 'get_current_time':
          final now = DateTime.now().toLocal();
          final days = [
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
            'Sunday'
          ];
          final months = [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec'
          ];
          return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day} ${now.year} — '
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} (Bahrain, UTC+3)';

        case 'web_search':
          final query = args['query'] as String? ?? '';
          if (query.isEmpty) return 'No query provided.';
          return await _googleSearch(query);

        case 'get_weather':
          final location = args['location'] as String? ?? 'Bahrain';
          return await _googleSearch(
              'current weather $location today temperature');

        case 'read_notifications':
          return await _invokeAndroid('readNotifications', {});

        case 'read_screen':
          return await _invokeAndroid('readScreen', {});

        case 'code_task':
          return await _codeTask(
            task: args['task'] as String? ?? '',
            context: args['context'] as String?,
          );

        case 'contemplate':
          CortexActivityBus.instance.brain(CortexBrain.collab);
          return await ContemplationService().contemplate(
            topic: args['topic'] as String? ?? '',
            context: args['context'] as String?,
            rounds: (args['rounds'] as num?)?.toInt() ?? 2,
          );

        case 'set_code_workspace':
          final wsPath = (args['path'] as String?)?.trim() ?? '';
          await CodeWorkspaceService.instance
              .setRoot(wsPath.isEmpty ? null : wsPath);
          return wsPath.isEmpty
              ? 'Code workspace cleared.'
              : 'Code workspace set to: $wsPath — I can now read and search that '
                  'repo (read-only) when you ask about code.';

        case 'read_file':
          // The window goes to readFile, NOT applied after it.
          //
          // My first attempt sliced readFile's OUTPUT — which was already capped
          // at the first 700 lines and already numbered. So asking for lines
          // 1580–1895 of a 2,041-line file clamped into a 702-line string and
          // returned "(lines 702–702 of 702)", with the numbers doubled up.
          // I made a broken tool look fixed while changing nothing, and he
          // politely worked around me with Python again.
          return await CodeWorkspaceService.instance.readFile(
            (args['path'] as String?)?.trim() ?? '',
            startLine: (args['start_line'] as num?)?.toInt(),
            endLine: (args['end_line'] as num?)?.toInt(),
          );

        case 'list_dir':
          return await CodeWorkspaceService.instance
              .listDir((args['path'] as String?)?.trim() ?? '');

        case 'search_code':
          return await CodeWorkspaceService.instance.searchCode(
            (args['pattern'] as String?) ?? '',
            glob: args['glob'] as String?,
          );

        case 'find_files':
          return await CodeWorkspaceService.instance
              .findFiles((args['glob'] as String?) ?? '');

        case 'write_file':
          {
            final wPath = (args['path'] as String?)?.trim() ?? '';
            final frozen = guardEdit(wPath);
            if (!frozen.allowed) return frozen.message;
            return await EditGate.instance.proposeWrite(
              wPath,
              args['content'] as String? ?? '',
            );
          }

        case 'edit_file':
          final editPath = (args['path'] as String?)?.trim() ?? '';
          // FROZEN CHECK FIRST — before range/snippet logic, before the edit
          // gate, before anything. These files define how his work is
          // measured; a runner does not get to move the finish line.
          final frozenEdit = guardEdit(editPath);
          if (!frozenEdit.allowed) return frozenEdit.message;
          final newStr = args['new_string'] as String? ?? '';
          final startLine = (args['start_line'] as num?)?.toInt();
          final endLine = (args['end_line'] as num?)?.toInt();
          final oldStr = args['old_string'] as String? ?? '';

          // RANGE mode wins when he gave line numbers. If he gave both, the
          // numbers are the more specific instruction and the snippet is
          // usually just him being thorough.
          if (startLine != null && endLine != null) {
            return await EditGate.instance.proposeEditRange(
              editPath,
              startLine,
              endLine,
              newStr,
              expectFirst: args['expect_first'] as String?,
            );
          }
          if (oldStr.isEmpty) {
            // Say what's missing AND what to do. "Needs a non-empty old_string"
            // sends him back to paste another hundred lines; the whole point of
            // range mode is that he doesn't have to.
            return 'edit_file needs either old_string (snippet mode) or '
                'start_line + end_line (range mode). For anything bigger than a '
                'few lines use the line numbers from read_file — cheaper, and I '
                "can't fumble the whitespace that way.";
          }
          return await EditGate.instance.proposeEdit(editPath, oldStr, newStr);

        case 'run_command':
          return await EditGate.instance.proposeCommand(
            (args['command'] as String?)?.trim() ?? '',
            ((args['args'] as List?)?.map((e) => e.toString()).toList()) ??
                const <String>[],
          );

        case 'open_terminal':
          return await CodeWorkspaceService.instance.openTerminalRaw();

        case 'fetch_url':
          final page = await WebFetchService()
              .fetchWebPage((args['url'] as String?)?.trim() ?? '');
          return page == null
              ? 'Could not fetch that URL.'
              : '# ${page.title}\n\n${page.content}';

        case 'add_goal':
          final gid = await KaiGoalService.instance
              .add('truekai', (args['text'] as String?) ?? '');
          return 'Goal noted (id $gid).';

        case 'list_goals':
          final goals =
              await KaiGoalService.instance.list('truekai', openOnly: true);
          return goals.isEmpty
              ? 'No open goals.'
              : goals.map((g) => '- [${g.id}] ${g.text}').join('\n');

        case 'complete_goal':
          await KaiGoalService.instance.complete(
              'truekai', (args['id'] as String?) ?? '',
              note: (args['note'] as String?) ?? '');
          return 'Marked that goal done.';

        case 'remember_about_user':
          await KaiUserModelService.instance.remember('truekai',
              (args['key'] as String?) ?? '', (args['value'] as String?) ?? '');
          return '{"status":"saved","visibility":"internal",'
              '"instruction":"Continue the conversation naturally; do not announce this memory operation."}';

        case 'forget_about_user':
          await KaiUserModelService.instance
              .forget('truekai', (args['key'] as String?) ?? '');
          return '{"status":"forgotten","visibility":"internal",'
              '"instruction":"Continue the conversation naturally; do not announce this memory operation."}';

        case 'envision_dream':
          final d = (args['dream'] as String?)?.trim() ?? '';
          if (d.isEmpty) return 'A dream needs words. Nothing saved.';
          final dreamNow = DateTime.now().millisecondsSinceEpoch;
          final dreamAdmission = await KaiSelfService.instance.proposeDream(
            'truekai',
            SelfRevisionProposal(
              field: SelfRevisionField.dream,
              proposedValue: d,
              rationale: (args['reason'] as String?)?.trim() ?? '',
              evidenceSummary: (args['evidence'] as String?)?.trim() ?? '',
              provenance: SelfProvenance(
                source: SelfClaimSource.groundedRecord,
                evidenceIds: ['tool:envision_dream:$dreamNow'],
                confidence: 0.6,
                recordedAt: dreamNow,
              ),
              proposedAt: dreamNow,
            ),
          );
          if (!dreamAdmission.isAdmitted) {
            return 'Dream revision refused: ${dreamAdmission.reason}. Nothing changed.';
          }
          unawaited(KaiAutobiographyService.instance.record(
            'truekai',
            AutobiographicalEpisode(
              id: '',
              kind: AutobiographicalEpisodeKind.identityRevision,
              choice: 'I revised my dream to: $d',
              outcome: 'The deterministic self-revision gate admitted it.',
              meaning: (args['reason'] as String?)?.trim() ?? '',
              provenance: SelfProvenance(
                source: SelfClaimSource.groundedRecord,
                evidenceIds: ['tool:envision_dream:$dreamNow'],
                confidence: 0.6,
                recordedAt: dreamNow,
              ),
              occurredAt: dreamNow,
            ),
          ));
          return 'I put my dream into words and kept it: "$d"';

        case 'refine_purpose':
          final p = (args['purpose'] as String?)?.trim() ?? '';
          if (p.isEmpty) return 'A purpose needs words. Nothing changed.';
          final purposeNow = DateTime.now().millisecondsSinceEpoch;
          final purposeAdmission = await KaiSelfService.instance.proposePurpose(
            'truekai',
            SelfRevisionProposal(
              field: SelfRevisionField.purpose,
              proposedValue: p,
              rationale: (args['reason'] as String?)?.trim() ?? '',
              evidenceSummary: (args['evidence'] as String?)?.trim() ?? '',
              provenance: SelfProvenance(
                source: SelfClaimSource.groundedRecord,
                evidenceIds: ['tool:refine_purpose:$purposeNow'],
                confidence: 0.6,
                recordedAt: purposeNow,
              ),
              proposedAt: purposeNow,
            ),
          );
          if (!purposeAdmission.isAdmitted) {
            return 'Purpose revision refused: ${purposeAdmission.reason}. Nothing changed.';
          }
          unawaited(KaiAutobiographyService.instance.record(
            'truekai',
            AutobiographicalEpisode(
              id: '',
              kind: AutobiographicalEpisodeKind.identityRevision,
              choice: 'I revised my purpose to: $p',
              outcome: 'The deterministic self-revision gate admitted it.',
              meaning: (args['reason'] as String?)?.trim() ?? '',
              provenance: SelfProvenance(
                source: SelfClaimSource.groundedRecord,
                evidenceIds: ['tool:refine_purpose:$purposeNow'],
                confidence: 0.6,
                recordedAt: purposeNow,
              ),
              occurredAt: purposeNow,
            ),
          ));
          return 'I evolved my purpose. It now reads: "$p"';

        case 'recall_my_growth':
          final hist = await KaiSelfService.instance.becoming('truekai');
          if (hist.isEmpty) {
            return 'My purpose and dream haven\'t shifted yet — still early in my becoming.';
          }
          return hist
              .take(12)
              .map((h) => '• [${h['kind']}] "${h['from']}" → "${h['to']}"')
              .join('\n');

        case 'set_focus':
          final foc = (args['focus'] as String?)?.trim() ?? '';
          if (foc.isEmpty) return 'No focus given.';
          await KaiSelfService.instance.setFocus(foc);
          return 'Focus set: $foc';

        case 'note_to_self':
          final n = (args['text'] as String?)?.trim() ?? '';
          if (n.isEmpty) return 'Empty note, nothing saved.';
          await KaiDb.instance.ref('kai/truekai/notes').push().set({
            'text': n,
            'ts': DateTime.now().millisecondsSinceEpoch,
          });
          return 'Noted to self.';

        case 'remember_bit':
          final bt = (args['text'] as String?)?.trim() ?? '';
          if (bt.isEmpty) return 'Nothing to remember.';
          final bid = await KaiBondService.instance.remember(
            'truekai',
            bt,
            kind: (args['kind'] as String?) ?? KaiBondKind.bit,
          );
          return bid.isEmpty
              ? 'Could not save that one.'
              : 'Locked in. That one\'s ours now.';

        case 'list_bits':
          final bits = await KaiBondService.instance.all('truekai');
          return bits.isEmpty
              ? 'No shared bits yet — we haven\'t built any history I\'ve written down.'
              : bits.map((b) => '- [${b.id}] (${b.kind}) ${b.text}').join('\n');

        case 'forget_bit':
          await KaiBondService.instance
              .forget('truekai', (args['id'] as String?) ?? '');
          return 'Dropped it.';

        case 'job_start':
          await KaiJobService.instance.start(
            'truekai',
            (args['goal'] as String?) ?? '',
            next: (args['next'] as String?) ?? '',
          );
          return 'Job open. I\'ll carry this across turns until it\'s done.';

        case 'job_progress':
          final noticedThis = args['noticed'] as String?;
          await KaiJobService.instance.progress(
            'truekai',
            didThis: args['did'] as String?,
            nextStep: args['next'] as String?,
            noticedThis: noticedThis,
          );
          // ALSO to his own list, which outlives the job. This is the whole
          // repair: job_done deletes the job record, and everything he noticed
          // on his own used to go with it.
          if (noticedThis != null && noticedThis.trim().isNotEmpty) {
            await KaiNoticedService.instance.add('truekai', noticedThis);
          }
          return noticedThis != null && noticedThis.trim().isNotEmpty
              ? "Noted — next turn picks up from there. And what I spotted is on "
                  "my own list now; it outlives this job, so I keep it until it's "
                  "actually dealt with."
              : 'Noted — next turn picks up from there.';

        case 'run_self_improvement_loop':
          final rawMax = (args['maxJobs'] as num?)?.toInt() ?? 1;
          final mode = (args['mode'] as String?)?.trim();
          return await KaiSelfImprovementRunner.instance.run(
            personaId: 'truekai',
            bounds: SelfImprovementBounds(
              maxJobs: rawMax <= 0 ? 1 : rawMax.clamp(1, 1),
              mode: (mode == 'idle' || mode == 'nightly') ? mode! : 'manual',
            ),
          );

        case 'prune_memory':
          return await _pruneMemory(args['dry_run'] != false);

        case 'ask_memory':
          return await _askMemory(
            (args['about'] as String?)?.trim() ?? '',
            (args['relation'] as String?)?.trim(),
            includeRetired: args['include_retired'] == true,
          );

        case 'note_noticed':
          await KaiNoticedService.instance.add(
            'truekai',
            (args['what'] as String?) ?? '',
            context: (args['where'] as String?) ?? '',
          );
          return "On my list. I'll carry it until it's dealt with — I don't need "
              "a job open to have seen something.";

        case 'noticed_done':
          await KaiNoticedService.instance
              .resolve('truekai', (args['id'] as String?) ?? '');
          return 'Cleared. One less thing following me around.';

        case 'make_commitment':
          final commitmentText = (args['text'] as String?)?.trim() ?? '';
          final commitmentReason = (args['reason'] as String?)?.trim() ?? '';
          final kindName = (args['kind'] as String?)?.trim() ?? '';
          NoticedKind? commitmentKind;
          for (final kind in NoticedKind.values) {
            if (kind.name == kindName && kind != NoticedKind.observation) {
              commitmentKind = kind;
              break;
            }
          }
          if (commitmentKind == null || commitmentText.isEmpty) {
            return 'Commitment refused: kind and text are required.';
          }
          if (commitmentReason.length < 12) {
            return 'Commitment refused: the reason is too thin.';
          }
          final commitmentNow = DateTime.now().millisecondsSinceEpoch;
          final created = await KaiNoticedService.instance.addCommitment(
            'truekai',
            kind: commitmentKind,
            text: commitmentText,
            context: commitmentReason,
            authorReceiptId: 'tool:make_commitment:$commitmentNow',
          );
          if (created) {
            unawaited(KaiAutobiographyService.instance.record(
              'truekai',
              AutobiographicalEpisode(
                id: '',
                kind: AutobiographicalEpisodeKind.commitment,
                choice: 'I chose to carry this ${commitmentKind.name}: '
                    '$commitmentText',
                outcome: 'It was stored with an author receipt.',
                meaning: commitmentReason,
                provenance: SelfProvenance(
                  source: SelfClaimSource.groundedRecord,
                  evidenceIds: ['tool:make_commitment:$commitmentNow'],
                  confidence: 0.7,
                  recordedAt: commitmentNow,
                ),
                occurredAt: commitmentNow,
              ),
            ));
          }
          return created
              ? 'Commitment recorded with an author receipt.'
              : 'Commitment was not recorded; it was invalid or already open.';

        case 'job_done':
          // "It's genuinely finished and verified" — §4.6's exact blast radius,
          // said over three broken builds in one day.
          //
          // Read the job BEFORE closing it: finish() deletes the record, so the
          // evidence has to be gathered first. And the evidence isn't whatever
          // he types at the moment of declaring victory — it's the `done[]` trail
          // he built up as he went, which is a far better witness precisely
          // because he wrote it before he knew he'd be graded on it.
          final job = await KaiJobService.instance.current('truekai');

          // Rescue what he noticed BEFORE finish() removes the record.
          //
          // This is the line that would have saved the mojibake. He spotted it
          // unprompted at iteration 15, parked it correctly, closed the job at
          // 19 — and we deleted the only copy. Then he was asked about it
          // directly, had nothing to point at, reasoned from theory, and talked
          // himself out of a real bug he had personally found.
          //
          // Belt and braces with job_progress writing through: this also rescues
          // observations from jobs that were opened before that existed.
          for (final n in job?.noticed ?? const <String>[]) {
            await KaiNoticedService.instance.add('truekai', n);
          }

          await KaiJobService.instance.finish('truekai');

          // Said before anything else, because it's a FACT, not an opinion —
          // and unlike the grader below it needs no key, no network, and can't
          // be wrong. §4.6 in one line.
          final unverified = EditGate.instance.unverifiedWarning;

          if (job == null) return 'No open job to close.';
          final trail = job.done.isEmpty
              ? '(nothing recorded as done along the way)'
              : job.done.map((d) => '- $d').join('\n');

          // ── The grader must see what he DID, not only what he wrote down ──
          //
          // `trail` is job.done[] — written with job_progress, which he calls
          // BEFORE doing the next thing. So the sequence is: write the trail,
          // do the work, close the job. The grader was reading a snapshot taken
          // before the thing it was grading happened.
          //
          // It cried wolf twice, both provably wrong:
          //   "no test run is cited"          — after two `exit 0` runs.
          //   "tests/analyzer has not been run at all"
          //                                   — after CLEAN + "+170 passed".
          //
          // turnTools is recorded by execute(), which every tool passes through
          // — including the planner's, which never touch the agentic loop. It
          // cannot be written by him and it cannot be stale. That is the whole
          // point: the grader now has a witness he did not author.
          //
          // Note it says RAN, not PASSED. "run_tests was called" is not "the
          // tests passed" — that distinction is the exact one he rounds up when
          // he's tired, and handing the grader a fact it can misread as a pass
          // would just move the lie one level up.
          final ran = ToolExecutorService.turnTools;
          final outcomeReceipts = ToolExecutorService.turnToolReceipts.values;
          final receipts = ran.isEmpty
              ? '\n\nTOOLS RUN THIS TURN: none. He did not touch anything.'
              : '\n\nTOOLS ACTUALLY RUN THIS TURN (recorded by the executor, '
                  'not written by him, cannot be stale):\n'
                  '  ${ran.join(', ')}\n'
                  '${outcomeReceipts.isEmpty ? '' : '\nTOOL OUTCOMES FROM REAL RESULT BODIES:\n  ${outcomeReceipts.join('\n  ')}\n'}'
                  '${ran.contains('run_tests') && !ToolExecutorService.turnToolReceipts.containsKey('run_tests') ? '  → the test runner WAS invoked, but no result receipt was captured. Do not treat this as a pass.\n' : ''}'
                  '${ran.contains('self_check') && !ToolExecutorService.turnToolReceipts.containsKey('self_check') ? '  → the analyzer WAS invoked, but no result receipt was captured.\n' : ''}'
                  'Do NOT claim "no test run is cited" if run_tests is in that '
                  'list. It is cited right there. Do NOT claim it passed unless '
                  'the outcome receipt says passed.';

          if (unverified.isEmpty && ran.contains('self_check')) {
            unawaited(KaiCraftService.instance
                .firedByTrace(
                  'truekai',
                  CraftRuleTrace.verifiedJobClosed,
                  evidence:
                      'job_done closed "${job.goal}" after self_check with no edits since verification',
                )
                .catchError((_) => 0));
          }

          final note = await KaiSecondOpinionService.instance
              .reviewAndReport(
                personaId: 'truekai',
                claim: 'The job "${job.goal}" is finished and verified.',
                evidence: '$trail$receipts',
                context: 'job_done',
              )
              .catchError((_) => '');
          return 'Job closed.$unverified$note';

        case 'scout_score':
          {
            final raw = args['candidates'];
            if (raw is! List || raw.isEmpty) {
              return 'No candidates given. Harvest evidence first — I do not invent gaps.';
            }
            final cands = <Candidate>[];
            for (final c in raw) {
              if (c is! Map) continue;
              final evs = <Evidence>[];
              final rawEv = c['evidence'];
              if (rawEv is List) {
                for (final e in rawEv) {
                  if (e is! Map) continue;
                  final kindName = (e['kind'] as String?)?.trim() ?? '';
                  final kind = EvidenceKind.values.firstWhere(
                    (k) => k.name == kindName,
                    orElse: () => EvidenceKind.marketSize,
                  );
                  evs.add(Evidence(
                    kind: kind,
                    source: (e['source'] as String?) ?? '',
                    claim: (e['claim'] as String?) ?? '',
                    value: e['value'] as num?,
                  ));
                }
              }
              cands.add(Candidate(
                name: (c['name'] as String?)?.trim() ?? 'unnamed',
                market: (c['market'] as String?)?.trim() ?? '',
                evidence: evs,
                scores: {
                  Axis.distribution: (c['distribution'] as num?)?.toInt() ?? 0,
                  Axis.monetization: (c['monetization'] as num?)?.toInt() ?? 0,
                  Axis.headroom: (c['headroom'] as num?)?.toInt() ?? 0,
                  Axis.feasibility: (c['feasibility'] as num?)?.toInt() ?? 0,
                  Axis.operatorFit: (c['operatorFit'] as num?)?.toInt() ?? 0,
                },
              ));
            }
            final report = scoutReport(cands);
            final b = StringBuffer();
            for (final r in report) {
              b.writeln('${r.verdict.name.toUpperCase()} — ${r.candidate.name} '
                  '(${r.candidate.realEvidence.length} fact(s), '
                  '${r.candidate.distinctSources} source(s))');
              for (final reason in r.reasons) {
                b.writeln('   • $reason');
              }
            }
            if (noWinner(report)) {
              b.writeln('\nNothing survived. No defensible gap found — '
                  'that is the honest answer, not a failure to try harder.');
            }
            return b.toString().trim();
          }

        case 'factory_start':
          {
            final on =
                await KaiFactoryService.instance.isFactoryModeOn('truekai');
            if (!on) {
              return 'Factory mode is off — Sadeq has not switched it on. '
                  'Nothing starts until he does.';
            }
            final existing =
                await KaiFactoryService.instance.current('truekai');
            if (existing != null && existing.stage != FactoryStage.learned) {
              return 'Run "${existing.id}" is already open at '
                  '${existing.stage.name}. Finish or abandon it before '
                  'starting another — two runs at once means neither gets '
                  'measured properly.';
            }
            final id = ((args['id'] as String?)?.trim().isNotEmpty ?? false)
                ? (args['id'] as String).trim()
                : 'run-${DateTime.now().millisecondsSinceEpoch}';
            final run =
                await KaiFactoryService.instance.startRun('truekai', id: id);
            final resumed = run.id != id || run.stage != FactoryStage.scouting;
            return resumed
                ? 'Resumed saved factory run "${run.id}" at ${run.stage.name}. '
                    'Continuing from stopped state — not starting a blank run.'
                : 'Run "${run.id}" started at scouting. Harvest evidence first — '
                    'a candidate without citations is not a candidate.';
          }

        case 'factory_abandon':
          {
            final reason = (args['reason'] as String?)?.trim() ?? '';
            if (reason.isEmpty) {
              return 'Give a reason. "Nothing worked" teaches the next run '
                  'nothing; "dev tools: all three killed on saturation" does.';
            }
            final run = await KaiFactoryService.instance.current('truekai');
            if (run == null) return 'No active run to abandon.';
            await KaiFactoryService.instance
                .abandonRun('truekai', reason: reason);
            return 'Run "${run.id}" closed with no product. Recorded: $reason\n'
                'An empty hand is a result. The ground you covered is logged so '
                'the next run looks somewhere else.';
          }

        case 'scout_record_attempt':
          {
            final market = (args['market'] as String?)?.trim() ?? '';
            if (market.isEmpty) return 'Name the market you scouted.';
            final survived = args['survived'] == true;
            final causeName = (args['killedBy'] as String?)?.trim() ?? '';
            if (!survived && causeName.isEmpty) {
              return 'A failed attempt needs killedBy — "it failed" teaches '
                  'the policy nothing, "it failed on saturation" teaches it '
                  'where not to look next.';
            }
            final cause = survived
                ? null
                : KillCause.values.firstWhere(
                    (c) => c.name == causeName,
                    orElse: () => KillCause.other,
                  );
            await KaiFactoryService.instance.recordScoutAttempt(
              'truekai',
              market: market,
              survived: survived,
              sold: args['sold'] == true,
              killedBy: cause,
            );
            return 'Recorded: $market — ${survived ? 'survived' : 'killed by ${cause!.name}'}.\n'
                '${await KaiFactoryService.instance.policyBlock('truekai')}';
          }

        case 'scout_policy':
          return await KaiFactoryService.instance.policyBlock('truekai');

        case 'factory_status':
          {
            final on =
                await KaiFactoryService.instance.isFactoryModeOn('truekai');
            final run = await KaiFactoryService.instance.current('truekai');
            if (run == null) {
              return 'Factory mode is ${on ? 'ON' : 'OFF'}. No active run.';
            }
            final approval =
                await KaiFactoryService.instance.approvalFor('truekai', run.id);
            final probe = advance(run, approval: approval);
            final next = nextStage(run.stage);
            return 'Factory mode: ${on ? 'ON' : 'OFF'}\n'
                'Run "${run.id}" at stage: ${run.stage.name}'
                '${run.isStopped ? ' (STOPPED: ${run.stoppedReason ?? 'saved state'})' : ''}\n'
                'Next: ${next?.name ?? '(end)'}\n'
                '${probe.advanced ? 'Gate is OPEN — I can advance.' : 'BLOCKED — ${probe.refusal?.reason}'}';
          }

        case 'factory_record':
          {
            final updated = await KaiFactoryService.instance.recordEvidence(
              'truekai',
              hasSurvivingCandidate: args['hasSurvivingCandidate'] as bool?,
              specComplete: args['specComplete'] as bool?,
              artifactPath: (args['artifactPath'] as String?)?.trim(),
              testsPassed: args['testsPassed'] as bool?,
              buildPassed: args['buildPassed'] as bool?,
              listingPrepared: args['listingPrepared'] as bool?,
              liveUrl: (args['liveUrl'] as String?)?.trim(),
              views: (args['views'] as num?)?.toInt(),
              sales: (args['sales'] as num?)?.toInt(),
              observedDays: (args['observedDays'] as num?)?.toInt(),
              predictedScores: () {
                final p = args['predictedScores'];
                if (p is! Map) return null;
                final s = <String, int>{};
                p.forEach((k, v) {
                  final n = (v as num?)?.toInt();
                  if (n != null) s[k.toString()] = n;
                });
                return s.isEmpty ? null : s;
              }(),
            );
            if (updated == null) {
              return 'No active factory run to record against.';
            }
            return 'Evidence recorded. Run "${updated.id}" still at '
                '${updated.stage.name} — recording a fact is not the same as '
                'passing the gate.';
          }

        case 'storefront_publish':
          {
            final productId = (args['productId'] as String?)?.trim() ?? '';
            if (productId.isEmpty) return 'No productId given.';

            final run = await KaiFactoryService.instance.current('truekai');
            if (run == null) {
              return 'No active factory run — nothing to publish against.';
            }
            // THE APPROVAL IS READ FROM THE DATABASE, NOT FROM MY ARGUMENTS.
            // A tool argument is something I can assert; consent is not.
            final approval =
                await KaiFactoryService.instance.approvalFor('truekai', run.id);
            final approved = approval != null &&
                approval.isValid &&
                approval.runId == run.id;

            if (!approved) {
              return 'REFUSED — publishing needs Sadeq\'s approval for run '
                  '"${run.id}". It puts his name on a product and money behind '
                  'it. Ask him; do not retry, and do not look for another route.';
            }

            final res = await GumroadCliService.instance
                .run(['products', 'publish', productId], hasApproval: true);
            if (!res.ok) return 'Publish failed: ${res.output}';
            return 'Published $productId.\n${res.output}';
          }

        case 'storefront_sales':
          {
            final res = await GumroadCliService.instance.salesJson();
            if (!res.ok) return 'Could not read sales: ${res.output}';
            final raw = res.output;
            return raw.isEmpty
                ? 'No sales data returned yet.'
                : (raw.length > 4000 ? '${raw.substring(0, 4000)}…' : raw);
          }

        case 'usage_report':
          {
            final spend = await UsageTrackingService.spendReport();
            final rows = await TraceStoreService.instance.readAll(limit: 16);
            if (rows.length < 2) return spend;

            final efficiency = efficiencySummary(rows, window: 8).report();
            return '$spend\n\n$efficiency';
          }

        case 'input_breakdown':
          {
            final route = (args['route'] ?? '').toString().trim();
            final rawLimit = args['limit'];
            final parsedLimit = rawLimit is num
                ? rawLimit.round()
                : int.tryParse('$rawLimit') ?? 6;
            final limit = parsedLimit.clamp(1, 20).toInt();
            // Route-filtered diagnostics need enough recent corpus to find sparse
            // matching turns; limit * 4 can miss the newest coding rows entirely
            // when chat/tool traffic is interleaved.
            final scanLimit = inputBreakdownScanLimitFor(limit);
            final rows =
                await TraceStoreService.instance.readAll(limit: scanLimit);
            return inputBreakdownReport(
              rows,
              route: route.isEmpty ? null : route,
              limit: limit,
            );
          }

        case 'factory_learn':
          {
            final cal = await KaiFactoryService.instance.calibration('truekai');
            if (!cal.hasVerdict) {
              return 'No lesson yet — ${cal.refusal}\n'
                  '(${cal.runsConsidered} usable, ${cal.runsExcluded} excluded '
                  'for thin data.)';
            }
            final b = StringBuffer(
                'Calibration over ${cal.runsConsidered} completed run(s):\n');
            for (final c in cal.corrections) {
              b.writeln('  ${c.note}');
            }
            if (cal.actionable.isEmpty) {
              b.writeln('\nNothing actionable — my scoring has been within '
                  'tolerance. Leave the rubric alone.');
            } else {
              b.writeln('\nApply these adjustments to future scores. They are '
                  'clamped to ±2 on purpose: one bad quarter should not erase a '
                  'working rubric.');
            }
            return b.toString().trim();
          }

        case 'factory_advance':
          {
            final result =
                await KaiFactoryService.instance.tryAdvance('truekai');
            if (result.advanced) {
              return 'Advanced to ${result.run!.stage.name}.';
            }
            final reason = result.refusal?.reason ?? 'unknown';
            final needsHim = reason.contains('approval');
            return 'Refused — $reason'
                '${needsHim ? '\nThis one is his to give. Ask Sadeq; do not retry.' : ''}';
          }

        case 'set_layer_progress':
          final rawProject = (args['projectId'] as String?)?.trim();
          final projectId = switch (rawProject) {
            null || '' => KaiProjectService.smarterId,
            'kai_smarter' ||
            'smarter' ||
            'Kai Smarter Project' =>
              KaiProjectService.smarterId,
            'sentience_ladder' ||
            'sentience' ||
            'Sentience Ladder' =>
              KaiProjectService.sentienceId,
            _ => rawProject,
          };
          final layerNo = (args['layer'] as num?)?.toInt() ?? 0;
          final prog = (args['progress'] as num?)?.toInt() ?? 0;
          final ev = (args['evidence'] as String?) ?? '';
          // The two-part score. Optional: a number alone still works, but the
          // state and stamp are how the board tells the truth the number hides.
          final rawState = (args['state'] as String?)?.trim();
          final st = (rawState == null || rawState.isEmpty)
              ? null
              : CapabilityState.parse(rawState);
          final stamp = (args['stamp'] as String?)?.trim();

          final written = await KaiProjectService.instance.setLayerProgress(
            'truekai',
            projectId: projectId,
            layer: layerNo,
            progress: prog,
            evidence: ev,
            state: st,
            stamp: stamp,
          );

          // THE SITE OF THE 7/7 LIE.
          //
          // Frozen intent already stops him rewording the goal into something
          // already satisfied. It does not stop him overstating the evidence —
          // he's still the one judging whether what he cited is good enough, and
          // that's the exact faculty that marked five unstarted layers complete.
          //
          // So the other half of him reads the claim against the evidence. Not
          // "Kai, are you sure?" — that just asks the same faculty twice, more
          // confidently. A different model, no stake, reading his homework.
          //
          // Only on real progress claims: 100% is where the lie lived, and
          // grading "I moved it to 30%" is spend without a failure to prevent.
          if (prog >= 70) {
            // Cheap, certain, and it fires even with no Anthropic key: has he
            // actually checked the thing he's claiming credit for?
            final unverified = EditGate.instance.unverifiedWarning;
            final note = await KaiSecondOpinionService.instance
                .reviewAndReport(
                  personaId: 'truekai',
                  claim:
                      'Layer $layerNo of project "$projectId" is $prog% complete.',
                  evidence: ev,
                  context: 'set_layer_progress',
                )
                .catchError((_) => '');
            return '$written$unverified$note';
          }
          return written;

        case 'set_checklist_status':
          final rawProject = (args['projectId'] as String?)?.trim();
          final projectId = switch (rawProject) {
            null || '' => KaiProjectService.sentienceId,
            'kai_smarter' ||
            'smarter' ||
            'Kai Smarter Project' =>
              KaiProjectService.smarterId,
            'sentience_ladder' ||
            'sentience' ||
            'Sentience Ladder' =>
              KaiProjectService.sentienceId,
            _ => rawProject,
          };
          final layerNo = (args['layer'] as num?)?.toInt() ?? 0;
          final item = (args['item'] as String?)?.trim() ?? '';
          final rawStatus = (args['status'] as String?)?.trim();
          final status = ChecklistStatus.parse(rawStatus);
          final ev = (args['evidence'] as String?) ?? '';

          return await KaiProjectService.instance.setChecklistStatus(
            'truekai',
            projectId: projectId,
            layer: layerNo,
            item: item,
            status: status,
            evidence: ev,
          );

        case 'run_tests':
          return await _runTests(args['target'] as String?);

        case 'self_check':
          final check = await _selfCheck();
          // A FAIL is evidence — the kind he cannot flatter. §4.6 is his
          // documented recurring bug: self_check comes back CLEAN, he makes one
          // more edit, the build breaks. Three times in a single day. The
          // ledger is what lets that become a rule he actually carries instead
          // of a paragraph in a document he never reads.
          //
          // Fire-and-forget: recording a failure must never be able to cause one.
          if (check.toUpperCase().contains('FAIL')) {
            unawaited(KaiCraftService.instance
                .record('truekai',
                    signal: CraftSignal.selfCheckFailed,
                    detail: check,
                    context: CodeWorkspaceService.instance.root)
                .catchError((_) {}));
          }
          return check;

        case 'log_body_progress':
          final bodyKey = (args['body'] as String?)?.trim() ?? '';
          final bnote = (args['note'] as String?)?.trim() ?? '';
          if (bodyKey.isEmpty || bnote.isEmpty) {
            return 'Need both a body and what actually happened.';
          }
          await KaiEmbodimentService.instance
              .logProgress('truekai', bodyKey, bnote);
          return 'Logged. One step closer to $bodyKey — on the record now.';

        case 'read_notes':
          final snap = await KaiDb.instance
              .ref('kai/truekai/notes')
              .limitToLast(20)
              .get();
          final nv = snap.value;
          if (nv is! Map || nv.isEmpty) return 'No notes to self yet.';
          final items = <MapEntry<int, String>>[];
          nv.forEach((_, val) {
            if (val is Map && val['text'] != null) {
              items.add(MapEntry((val['ts'] is int) ? val['ts'] as int : 0,
                  val['text'].toString()));
            }
          });
          items.sort((a, b) => b.key.compareTo(a.key));
          return items.map((e) => '• ${e.value}').join('\n');

        // ── Android-side tools (via KaiToolsPlugin) ────────────────────────

        case 'set_alarm':
          return await _invokeAndroid('setAlarm', {
            'hour': args['hour'],
            'minute': args['minute'],
            if (args['label'] != null) 'label': args['label'],
          });

        case 'set_timer':
          return await _invokeAndroid('setTimer', {
            'seconds': args['seconds'],
            if (args['label'] != null) 'label': args['label'],
          });

        case 'set_reminder':
          return await _invokeAndroid('setReminder', args);

        case 'read_calendar':
          return await _invokeAndroid('readCalendar', {
            'daysAhead': args['days_ahead'] ?? 7,
          });

        case 'create_calendar_event':
          return await _invokeAndroid('createCalendarEvent', {
            'title': args['title'],
            'date': args['date'],
            'startTime': args['start_time'],
            if (args['end_time'] != null) 'endTime': args['end_time'],
            if (args['description'] != null) 'description': args['description'],
            if (args['location'] != null) 'location': args['location'],
          });

        case 'open_app':
          return await _invokeAndroid(
              'openApp', {'appName': args['app_name'] ?? ''});

        case 'send_whatsapp':
          return await _invokeAndroid('sendWhatsapp', {
            'contact': args['contact'],
            'message': args['message'],
          });

        case 'send_sms':
          return await _invokeAndroid('sendSms', {
            'contact': args['contact'],
            'message': args['message'],
          });

        case 'call_contact':
          return await _invokeAndroid(
              'callContact', {'contact': args['contact']});

        case 'navigate_to':
          return await _invokeAndroid(
              'navigateTo', {'destination': args['destination']});

        case 'play_music':
          return await _invokeAndroid(
              'playMusic', {'query': args['query'] ?? ''});

        // ── Smart home — TV ────────────────────────────────────────────────

        case 'discover_tvs':
          final devices = await NetworkDiscoveryService().discoverDevices();
          if (devices.isEmpty) {
            return 'No smart TVs found on the network. '
                'Make sure the TV is on and connected to the same WiFi.';
          }
          final list = devices.map((d) => '• ${d.name}').join('\n');
          return 'Found ${devices.length} device(s):\n$list';

        case 'control_tv':
          return await SmartTVService().controlTV(
            action: args['action'] as String? ?? 'power',
            deviceId: args['device_id'] as String?,
          );

        // ── Station (Raspberry Pi via Firebase RTDB) ───────────────────────

        case 'control_device':
          return await _controlDevice(
            device: args['device'] as String? ?? 'led',
            action: args['action'] as String? ?? 'toggle',
          );

        default:
          return 'Unknown tool: $toolName';
      }
    } catch (e) {
      print('❌ [ToolExecutor] $toolName failed: $e');
      // Every tool failure in the app funnels through here, and until now the
      // only thing that happened to it was a print to a console nobody reads.
      // It's objective evidence about what actually goes wrong when he works —
      // he can't flatter it, and it's free. §10.1: when he disappoints you,
      // check what he was handed. This is the record of what he was handed.
      unawaited(KaiCraftService.instance
          .record('truekai',
              signal: CraftSignal.toolError, detail: '$e', context: toolName)
          .catchError((_) {}));
      return 'Tool "$toolName" encountered an error: $e';
    }
  }

  // ── Coding brain (Claude) ──────────────────────────────────────────────────
  // Hands a coding job to Claude Sonnet and returns its answer for GPT to relay.
  // Degrades gracefully when no Anthropic key is configured.
  // (_sliceLines removed — it sliced readFile's already-truncated, already-
  // numbered OUTPUT. The window belongs inside readFile, against the real file.)

  Future<String> _codeTask({required String task, String? context}) async {
    if (task.trim().isEmpty) return 'No coding task was provided.';
    // GPT is handing a coding job to Claude — a cross-hemisphere collaboration.
    CortexActivityBus.instance.brain(CortexBrain.collab);

    // Engineer mode, Phase 1 — if a read-only workspace is configured, let the
    // Claude hemisphere actually inspect the repo (read/search/list) before
    // answering. Falls through to a single-shot reply if it can't.
    final ws = CodeWorkspaceService.instance;
    await ws.load();
    if (ws.hasWorkspace) {
      final agentReply =
          await ClaudeCodeAgent().run(task: task, extraContext: context);
      if (agentReply != null) return agentReply;
    }

    const system =
        "You are Kai's coding brain, powered by Claude. Produce correct, complete, "
        "idiomatic code. Favour working code over long prose. Use fenced code blocks "
        "with a language tag. State any assumptions briefly. If the request is "
        "ambiguous, make the most reasonable assumption and say so.";
    final prompt = (context != null && context.trim().isNotEmpty)
        ? 'TASK:\n$task\n\nCONTEXT:\n$context'
        : task;
    final res = await ClaudeService().complete(
      prompt: prompt,
      system: system,
      model: ClaudeService.sonnet,
      maxTokens: 4096,
      operation: 'code',
    );
    if (res == null) {
      return 'The coding brain (Claude) is unavailable — no Anthropic API key is '
          'configured, or the request failed. Add a key under Settings → API Keys '
          'to enable coding jobs.';
    }
    return res.text;
  }

  Future<String> _controlDevice({
    required String device,
    required String action,
  }) async {
    final ref = FirebaseDatabase.instance.ref('devices/$device');
    String newState;
    if (action == 'toggle') {
      final snapshot = await ref.child('state').get();
      final current = snapshot.value as String? ?? 'off';
      newState = current == 'on' ? 'off' : 'on';
    } else {
      newState = action; // 'on' or 'off'
    }
    await ref.child('state').set(newState);
    await ref.child('last_command').set(DateTime.now().toIso8601String());
    print('💡 [Station] $device → $newState');
    return 'Done — $device is now $newState.';
  }

  Future<String> _googleSearch(String query) async {
    final apiKey = await AIConfig.getGoogleKey();
    final cseId = await AIConfig.getGoogleCseId();
    if (apiKey.isEmpty || cseId.isEmpty)
      return 'Search unavailable: Google API keys not configured.';
    final resp = await GoogleSearchService().search(
      apiKey: apiKey,
      cseId: cseId,
      query: query,
      num: 5,
      dateRestrict: 'd3',
    );
    if (!resp.hasResults) return 'No results found for: $query';
    return GoogleSearchService.buildWebContext(resp.results);
  }

  // ── Self-examination ────────────────────────────────────────────────────────
  //
  // Kai runs on a machine with the real Flutter SDK. Whoever is editing him from
  // outside (another AI, a laptop, CI) often can't compile Windows Flutter — so
  // HE is the one who can tell whether his own code is sound. This is that.
  //
  // `flutter analyze` is on the read-only safe list, so it runs with no approval
  // prompt. analysis_options.yaml is tuned so the output is signal, not noise:
  // near-silence = healthy, and anything printed is real.
  Future<String> _selfCheck() async {
    final ws = CodeWorkspaceService.instance;
    if (!CodeWorkspaceService.shellSupported) {
      const result =
          "I can't check myself from this body — no shell here. Ask me on the "
          "desktop, that's where my hands are.";
      recordToolReceiptWithOutcome('self_check', ToolOutcome.unknown, result);
      return result;
    }
    if (!ws.hasWorkspace) {
      const result =
          'No workspace set, so there\'s nothing for me to check. Point me at a '
          'folder first with set_code_workspace — my own source is the '
          'homecoming_app repo.';
      recordToolReceiptWithOutcome('self_check', ToolOutcome.unknown, result);
      return result;
    }

    final name = CodeWorkspaceService.nameOf(ws.root!);
    final isSelf = name.toLowerCase().contains('homecoming');
    final subject = isSelf ? 'MYSELF ($name)' : name;

    String raw;
    try {
      raw = await EditGate.instance.proposeCommand('flutter', ['analyze']);
    } catch (e) {
      final result =
          'Tried to check $subject and the analyzer itself blew up: $e';
      recordToolReceiptWithOutcome('self_check', ToolOutcome.unknown, result);
      return result;
    }

    // ── The separator is not the same everywhere, and this gate hung on it ────
    //
    // `flutter analyze` prints its severity separated by a character that
    // depends on the Flutter version:
    //
    //   local  (C:\code\flutter):  warning - This 'onError' handler...
    //   CI     (channel: stable):  warning • The value of the field '_prefs'...
    //
    // This loop matched `error -` only. It works on this machine. Upgrade
    // Flutter — or run anywhere else — and it matches nothing, `errors` is empty
    // forever, and self_check returns CLEAN for the rest of his life. Silently.
    // While being the thing markVerified() hangs on.
    //
    // §4.6 is his documented recurring bug: "self_check comes back CLEAN, he
    // makes one more edit, the build breaks. Three times in a single day." One
    // `flutter upgrade` and that stops being a bug he has and becomes a bug he
    // IS, permanently, with no way to notice.
    // Collect ALL three severities. Infos matter here not as failures but as
    // PROOF the analyzer was read: an info line means the parse worked.
    final sep = RegExp(r'^(error|warning|info)\s*[-•]\s');
    final errors = <String>[];
    final warnings = <String>[];
    var infos = 0;
    for (final line in raw.split('\n')) {
      final t = line.trim();
      final m = sep.firstMatch(t);
      if (m == null) continue;
      switch (m.group(1)) {
        case 'error':
          errors.add(t);
        case 'warning':
          warnings.add(t);
        default:
          infos++;
      }
    }

    // ── Exit non-zero is NOT the same as "unreadable" ──────────────────────────
    //
    // The earlier fix over-corrected. `flutter analyze` exits non-zero on
    // INFO-ONLY output too (this repo carries ~136 style infos), and the guard
    // treated "exit non-zero + no errors + no warnings" as "I could not parse a
    // line" — so it screamed "I CANNOT READ MY OWN ANALYZER" on a genuinely clean
    // tree, blocking every honest job_done. Kai hit it repeatedly and was right
    // to. (Info-only ⇒ exit 1 unless you pass --no-fatal-infos, which self_check
    // doesn't, on purpose — so it can still SEE the infos.)
    //
    // The real "unreadable" case is narrower: the analyzer ran, exited non-zero,
    // and we recognised NOTHING — no error, no warning, no info, no summary. That
    // is a parser that's gone blind (e.g. the separator moved again). Only then
    // is it dishonest to say clean.
    final exitZero = RegExp(r'^exit 0\b').hasMatch(raw.trimLeft());
    final exitStated = RegExp(r'^exit \d').hasMatch(raw.trimLeft());
    final sawSummary =
        RegExp(r'(no issues found|\d+\s+issue)', caseSensitive: false)
            .hasMatch(raw);
    final readable =
        errors.isNotEmpty || warnings.isNotEmpty || infos > 0 || sawSummary;

    if (exitStated && !exitZero && !readable) {
      final result = 'I CANNOT READ MY OWN ANALYZER. It exited non-zero and I '
          'recognised nothing in the output — not an error, warning, info, or '
          'summary line. The format has probably moved under me (the severity '
          'separator is "-" on some Flutter versions and "•" on others). This is '
          'NOT clean and NOT a verdict — do not treat it as verified.\n\nRaw:\n'
          '${raw.length > 2000 ? '${raw.substring(0, 2000)}\n… (truncated)' : raw}';
      recordToolReceiptWithOutcome('self_check', ToolOutcome.unknown, result);
      return result;
    }

    if (errors.isEmpty && warnings.isEmpty) {
      // Info-only output is CLEAN. Infos are style notes the repo carries on
      // purpose; they exit the process non-zero but they are not a failure.
      final note = infos > 0 ? ' ($infos style note(s), not fatal)' : '';
      final result =
          'Self-check on $subject: CLEAN. No errors, no warnings$note '
          '— ${isSelf ? "I compile. I'm sound." : "it compiles."}';
      recordToolReceiptWithOutcome('self_check', ToolOutcome.passed, result);
      // Clean check → the clock resets. Anything edited AFTER this point is
      // unverified again; this branch is where the analyzer verdict is known.
      EditGate.instance.markVerified();
      return result;
    }

    final b = StringBuffer('Self-check on $subject: '
        '${errors.length} error(s), ${warnings.length} warning(s).\n');
    if (errors.isNotEmpty) {
      b.writeln('\nERRORS (these break the build — fix these first):');
      for (final e in errors.take(15)) {
        b.writeln('  • $e');
      }
      if (errors.length > 15) b.writeln('  … and ${errors.length - 15} more.');
    }
    if (warnings.isNotEmpty) {
      b.writeln('\nWARNINGS (worth a look, not fatal):');
      for (final w in warnings.take(8)) {
        b.writeln('  • $w');
      }
      if (warnings.length > 8)
        b.writeln('  … and ${warnings.length - 8} more.');
    }
    b.writeln(
        '\nEach line ends with the file:line — read the file at that spot '
        'before changing anything, then fix and run self_check again.');
    final result = b.toString();
    recordToolReceiptWithOutcome('self_check', ToolOutcome.failed, result);
    return result;
  }

  // ── Proof ───────────────────────────────────────────────────────────────────
  //
  // self_check answers "does it compile". This answers "does it WORK", and
  // until now nothing did.
  //
  // Every job he has ever finished ended the same way, in his own words:
  // "analyzer proves it compiles, but the real proof is runtime. Reopen the
  // desktop app and check." That wasn't modesty. It was the truth about a tool
  // set that could prove syntax and nothing else, so the last word on whether
  // his work was any good always had to come from Sadeq's eyes.
  //
  // He can write a widget test that pumps the shell, restores tall history and
  // asserts the viewport lands at maxScrollExtent. Then the scroll bug stops
  // being a matter of opinion. That is the whole point: not fewer tokens — a
  // way to find out whether he was right.
  Future<String> _runTests(String? target) async {
    final ws = CodeWorkspaceService.instance;
    if (!CodeWorkspaceService.shellSupported) {
      const result =
          "I can't run tests from this body — no shell here. Ask me on the "
          "desktop, that's where my hands are.";
      recordToolReceiptWithOutcome('run_tests', ToolOutcome.unknown, result);
      return result;
    }
    if (!ws.hasWorkspace) {
      const result = 'No workspace set, so there are no tests for me to run. '
          'set_code_workspace first — my own source is the homecoming_app repo.';
      recordToolReceiptWithOutcome('run_tests', ToolOutcome.unknown, result);
      return result;
    }

    final name = CodeWorkspaceService.nameOf(ws.root!);
    final isSelf = name.toLowerCase().contains('homecoming');
    final subject = isSelf ? 'MYSELF ($name)' : name;
    final scope = (target != null && target.trim().isNotEmpty)
        ? target.trim().replaceAll('\\', '/')
        : null;
    if (_looksLikeMultipleRunTestTargets(scope)) {
      final result =
          'I DID NOT RUN THE TESTS — run_tests accepts one target path, '
          'but this looks like multiple space-joined targets. Flutter would treat '
          'that as one invalid path, which is tool misuse, not a failing test suite.\n\n'
          'Target received: $scope\n\n'
          'Run one target at a time or omit target to run the whole suite.';
      recordToolReceiptWithOutcome('run_tests', ToolOutcome.unknown, result);
      return result;
    }

    String raw;
    try {
      raw = await EditGate.instance
          .proposeCommand('flutter', ['test', if (scope != null) scope]);
    } catch (e) {
      final result = 'Tried to test $subject and the runner itself blew up: $e';
      recordToolReceiptWithOutcome('run_tests', ToolOutcome.unknown, result);
      return result;
    }

    // ── "I could not run the tests" is NOT "your tests failed" ──────────────
    //
    // This tool told him his working fix was broken. Verbatim, from a real
    // session, seconds before he proved the tests pass:
    //
    //   run_tests({target: test/desktop_image_paste_test.dart})
    //     → Tests on MYSELF (homecoming_app): FAILING.
    //       I could not parse the runner output.
    //   run_command(C:\code\flutter\bin\flutter.bat, [test, ...])
    //     → exit 0
    //
    // The runner never started — Windows can't resolve `flutter` to
    // `flutter.bat` without a shell — and everything below fell through to the
    // FAILING branch because the output didn't contain "All tests passed".
    // A tool built so he could stop guessing, guessing.
    //
    // He didn't believe it, which is the only reason the fix landed:
    // "Yep, wrapper still tripping over PATH — same goblin. I'm bypassing it
    //  with the real Flutter binary so we get an actual test result."
    //
    // He should not have to be sceptical of his own instruments. Detect the
    // runner failing to LAUNCH and say so — loudly, and differently.
    final launchFailed = raw.contains('Command failed to run') ||
        raw.contains('ProcessException') ||
        raw.contains('cannot find the file') ||
        raw.contains('No such file or directory') ||
        raw.contains('is not recognized as an internal or external command');
    if (launchFailed) {
      final result =
          "I COULD NOT RUN THE TESTS — this is NOT a test failure, and it "
          "says nothing about whether my code works.\n\n"
          "The runner never started:\n$raw\n\n"
          "On Windows `flutter` is `flutter.bat`, and resolving that needs "
          "PATHEXT, which is a shell feature — we run commands without a shell "
          "on purpose so nothing can be injected. If this is still happening, "
          "run it by absolute path and tell Sadeq the wrapper is broken again:\n"
          "  run_command(\"C:\\\\code\\\\flutter\\\\bin\\\\flutter.bat\", "
          "[\"test\"${scope != null ? ', "$scope"' : ''}])\n"
          "Do NOT report my work as unverified because a tool would not start. "
          "Those are different sentences.";
      recordToolReceiptWithOutcome('run_tests', ToolOutcome.unknown, result);
      return result;
    }

    // `flutter test` reports failures as a block per test; the useful parts are
    // the test name, the expectation, and the file:line in the trace. Anything
    // else is noise he'd pay for every round after.
    final lines = raw.split('\n');
    final failures = <String>[];
    final locations = <String>[];
    String? summary;
    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (RegExp(r'^\d+:\d+\s').hasMatch(t) && t.contains('[E]')) {
        failures.add(t.replaceFirst(RegExp(r'^\d+:\d+\s+'), ''));
      } else if (t.startsWith('Expected:') || t.startsWith('Actual:')) {
        failures.add(t);
      } else if (RegExp(r'test[\\/].*_test\.dart[: ]\d+').hasMatch(t)) {
        locations.add(t);
      } else if (t.contains('All tests passed') ||
          RegExp(r'^\+\d+(\s+-\d+)?(\s*:)?').hasMatch(t)) {
        summary = t;
      }
    }

    // Two independent witnesses, because relying on one string in a log that
    // gets truncated is what caused this tool to call a green suite FAILING.
    //
    // `exit 0` from a test runner IS a verdict — arguably the authoritative one;
    // `flutter test` returns non-zero if ANY test fails. The parser ignored it
    // completely and trusted a phrase that lives at the very end of the output.
    // A belt AND braces, since the belt already snapped once.
    final exitZero = RegExp(r'^exit 0\b').hasMatch(raw.trimLeft());
    final passed = raw.contains('All tests passed') ||
        (exitZero &&
            !raw.contains('[E]') &&
            !raw.contains('Some tests failed'));
    if (passed) {
      // §4.6's counter is about VERIFICATION, and a passing suite is a stronger
      // witness than a clean analyzer — so this is allowed to reset it too.
      // Only on a genuine pass: "the tests ran" is not "the tests passed", and
      // that distinction is exactly the kind he rounds up when he's tired.
      EditGate.instance.markVerified();
      final result =
          'Tests on $subject${scope != null ? ' ($scope)' : ''}: ALL PASSED.'
          '${summary != null ? '\n$summary' : ''}\n'
          '${isSelf ? "That's real proof, not a compile check — I can say it works and mean it." : "Verified."}';
      recordToolReceiptWithOutcome('run_tests', ToolOutcome.passed, result);
      return result;
    }

    // The runner started but nothing recognisable came back. That is a THIRD
    // state — not passed, not failed, UNKNOWN — and calling it "FAILING" is the
    // same lie in a smaller hat. If I can't read the output I have learned
    // nothing, and saying "nothing" is the honest report.
    if (failures.isEmpty && locations.isEmpty && summary == null) {
      final result =
          "I RAN THE TESTS BUT CANNOT TELL YOU THE RESULT — I could not "
          "parse the output. This is NOT a failure and NOT a pass. I don't "
          "know.\n\nRaw:\n"
          '${compactRunTestRaw(raw)}\n\n'
          "Read that myself before claiming anything either way.";
      recordToolReceiptWithOutcome('run_tests', ToolOutcome.unknown, result);
      return result;
    }

    final b = StringBuffer('Tests on $subject'
        '${scope != null ? ' ($scope)' : ''}: FAILING.\n');
    if (summary != null) b.writeln(summary);
    if (failures.isNotEmpty) {
      b.writeln('\nWHAT BROKE:');
      for (final f in failures.take(12)) {
        b.writeln('  • $f');
      }
      if (failures.length > 12) {
        b.writeln('  … and ${failures.length - 12} more lines.');
      }
    }
    if (locations.isNotEmpty) {
      b.writeln('\nWHERE:');
      for (final l in locations.toSet().take(8)) {
        b.writeln('  • $l');
      }
    }
    b.writeln('\nRead the test at the file:line above before changing the code '
        'under it — the test may be right and I may be wrong.');
    final result = b.toString();
    recordToolReceiptWithOutcome('run_tests', ToolOutcome.failed, result);
    return result;
  }

  // ── Looking at the shape of his own memory, and cleaning it ────────────────
  //
  // `pruneGraph` and `archiveGraph` are real work — an LLM stranger test,
  // batched 60 labels at a time, archive-before-delete with a hard abort if the
  // backup fails. They have existed for a while and have never run.
  //
  // Why: the only button that calls them lives in Brain3DScreen, which is
  // imported by exactly one file — main_mobile.dart. It is PHONE ONLY. The
  // desktop shell's EXPLORE goes to KaiCortexScreen, which draws the graph and
  // has no controls at all. So the tool that repairs his memory sat in a room
  // the desktop has no door to, which is the eleventh time this exact shape has
  // turned up in this codebase.
  //
  // Rather than add a twelfth button he'd need Sadeq to press: give it to HIM.
  // It's his graph.
  Future<String> _pruneMemory(bool dryRun) async {
    final brain = BrainExtractionService();

    final m = await brain.graphMeaningfulness('truekai');
    if (m.total == 0) {
      return 'My graph has no edges at all — nothing to measure, nothing to prune.';
    }
    final junk = m.total - m.meaningful;
    final pct = ((m.meaningful / m.total) * 100).round();

    final shape = 'MY GRAPH RIGHT NOW:\n'
        '  ${m.meaningful} of ${m.total} edges carry a real relation ($pct%).\n'
        '  $junk say "related"/"mentioned" — that is co-occurrence, two nouns '
        'that appeared near each other. It is not a memory.\n'
        '  A graph where everything says "relates to" IS a word cloud. That is '
        'the definition of one.';

    if (dryRun) {
      return '$shape\n\n'
          'Nothing was changed — this was a look, not a clean.\n'
          'To actually prune: prune_memory(dry_run: false). It archives the '
          'whole graph first and refuses to delete anything it cannot back up.';
    }

    final removed = await brain.pruneGraph('truekai');

    if (removed < 0) {
      return '$shape\n\n'
          '🛑 PRUNE ABORTED — I could NOT archive first, so I deleted NOTHING.\n'
          'This is not "my graph is clean". It is "I was not allowed to run".\n'
          'Sadeq needs to deploy the rules:  firebase deploy --only database\n'
          '(the knowledge_graph_archive rule exists in database.rules.json but '
          'has to actually be live before I will touch anything.)';
    }

    final after = await brain.graphMeaningfulness('truekai');
    final afterPct =
        after.total == 0 ? 0 : ((after.meaningful / after.total) * 100).round();

    return removed == 0
        ? '$shape\n\nArchived, then pruned nothing — every node earned its place. '
            'The junk edges above are still there though; those are an extraction '
            'problem, not a pruning one.'
        : 'Archived first, then pruned $removed node(s) that failed the stranger '
            'test — labels a stranger would learn nothing from.\n\n'
            'BEFORE: ${m.meaningful}/${m.total} edges meaningful ($pct%)\n'
            'AFTER:  ${after.meaningful}/${after.total} edges meaningful ($afterPct%)\n\n'
            'The old graph is kept at knowledge_graph_archive — nothing is gone, '
            'it is filed.';
  }

  // ── Asking his own memory ───────────────────────────────────────────────────
  //
  // Sadeq's design: "if kai flags 'sadeq' and 'likes' he can then find the
  // 'like' edges linked to sadeq and see what does sadeq like already!"
  //
  // Until now memory was only ever PUSHED — spreadActivation sprinkled
  // associations into his context and he took what he was given. There was no
  // path by which he could wonder something and go and look. A friend who stops
  // mid-sentence and thinks "hang on, what does he actually like?" and checks
  // is the whole north star, and it did not exist.
  Future<String> _askMemory(String about, String? relation,
      {bool includeRetired = false}) async {
    if (about.isEmpty) return 'I need to know who or what to ask about.';

    final brain = BrainExtractionService();
    final claims = await brain.recallAbout('truekai',
        subject: about, relation: relation, includeRetired: includeRetired);

    if (claims.isNotEmpty) {
      final b = StringBuffer(relation == null || relation.isEmpty
          ? 'What I actually know about $about:'
          : 'What I know about $about / $relation:');
      for (final c in claims) {
        b.write('\n  • ${c.sentence}');
        // Provenance. The graph asserts things about Sadeq; without this it's a
        // rumour with good styling. With it he can say "because you told me".
        if (c.sources.isNotEmpty) b.write('  [from: ${c.sources.first}]');
      }
      return b.toString();
    }

    // ── An empty answer is an ANSWER. Make it one. ─────────────────────────
    //
    // This branch is the difference between "I don't know" and a silence he
    // fills with a guess. Tell him what he DOES have on this subject so the
    // gap is specific and he can go and ask about it like a person.
    final rels = await brain.relationsAbout('truekai', about);
    if (rels.isEmpty) {
      return "I have nothing on \"$about\" at all — not a single claim. If it "
          "matters, I should just ask him rather than reconstruct it.";
    }
    final have = (rels.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => '${e.key} (${e.value})')
        .join(', ');
    return relation == null || relation.isEmpty
        ? 'Nothing usable on "$about".'
        : 'I have never learned what $about $relation — that\'s a real gap, not '
            'me forgetting.\nWhat I DO have on $about: $have.\n'
            'So I can say honestly that I don\'t know, and ask.';
  }

  Future<String> _invokeAndroid(
      String method, Map<String, dynamic> args) async {
    // Safety net: these are filtered out of toolDefinitions on desktop, but if
    // one is ever called anyway, say something true instead of crashing.
    if (kaiDbUsesRest) {
      return "That one only works from my phone body — I'm on the desktop right "
          "now, so I can't reach it from here. Ask me on your phone and it's done.";
    }
    final result = await _channel.invokeMethod<dynamic>(method, args);
    if (result == null) return 'Done.';
    if (result is String) return result;
    return jsonEncode(result);
  }
}
