// Tool Executor Service — Kai's agentic function calling dispatcher.
//
// Tool *schemas* (toolDefinitions) are injected into every GPT chat call.
// When GPT decides to call a tool, the result comes here to be executed.
// Dart-side tools are handled directly; Android system actions are
// delegated to KaiToolsPlugin via the 'com.homecoming.app/kai_tools' channel.
//
// Tool name mapping:
//   snake_case (GPT-facing)  →  camelCase (Android method name)

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../ai/ai_config.dart';
import '../ai/claude_service.dart';
import '../ai/claude_code_agent.dart';
import '../ai/contemplation_service.dart';
import '../ai/google_search_service.dart';
import 'cortex_activity_bus.dart';
import 'code_workspace_service.dart';
import '../smarthome/network_discovery_service.dart';
import '../smarthome/smart_tv_service.dart';

class ToolExecutorService {
  static const _channel = MethodChannel('com.homecoming.app/kai_tools');

  // ── Tool schemas — injected into every GPT API call ──────────────────────

  static const List<Map<String, dynamic>> toolDefinitions = [
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
              'description': 'The search query. Be specific for better results.',
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
              'description': 'City or country name, e.g. "Bahrain", "Dubai", "London"',
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
        'description': 'Set an alarm on the user\'s phone at a specific time of day.',
        'parameters': {
          'type': 'object',
          'properties': {
            'hour':   {'type': 'integer', 'description': 'Hour in 24h format (0–23)'},
            'minute': {'type': 'integer', 'description': 'Minute (0–59)'},
            'label':  {'type': 'string',  'description': 'Optional label for the alarm'},
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
            'year':   {'type': 'integer', 'description': 'Year (e.g. 2025)'},
            'month':  {'type': 'integer', 'description': 'Month 1–12'},
            'day':    {'type': 'integer', 'description': 'Day of month 1–31'},
            'hour':   {'type': 'integer', 'description': 'Hour in 24h format (0–23)'},
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
        'description':
            'Read upcoming events from the user\'s Google Calendar. '
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
        'description':
            'Add a new event to the user\'s calendar. '
            'Ask for any missing required details (title, date, time) before calling. '
            'Use today\'s date if the user says "today".',
        'parameters': {
          'type': 'object',
          'properties': {
            'title':       {'type': 'string', 'description': 'Event title / name'},
            'date':        {'type': 'string', 'description': 'Date in YYYY-MM-DD format'},
            'start_time':  {'type': 'string', 'description': 'Start time in HH:MM 24h format'},
            'end_time':    {'type': 'string', 'description': 'End time HH:MM (optional, defaults to +1h)'},
            'description': {'type': 'string', 'description': 'Optional event notes'},
            'location':    {'type': 'string', 'description': 'Optional venue or address'},
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
              'description': 'App name, e.g. "Maps", "Camera", "Spotify", "WhatsApp", "Settings"',
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
        'description':
            'Send a WhatsApp message to a contact. '
            'If the user only says "message X" without saying what to write, ask what to say first.',
        'parameters': {
          'type': 'object',
          'properties': {
            'contact': {
              'type': 'string',
              'description': 'Contact name (e.g. "Mom") or phone number with country code',
            },
            'message': {'type': 'string', 'description': 'The message text to send'},
          },
          'required': ['contact', 'message'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'send_sms',
        'description':
            'Send an SMS text message to a contact or phone number. '
            'Use when the user asks to "text" or "SMS" someone.',
        'parameters': {
          'type': 'object',
          'properties': {
            'contact': {
              'type': 'string',
              'description': 'Contact name or phone number with country code',
            },
            'message': {'type': 'string', 'description': 'The SMS message text'},
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
              'description': 'Contact name (e.g. "Dad") or phone number with country code',
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
        'description':
            'Open Google Maps and start navigation to a destination. '
            'Use when the user asks to "get directions", "navigate to", or "take me to" a place.',
        'parameters': {
          'type': 'object',
          'properties': {
            'destination': {
              'type': 'string',
              'description': 'Destination address or place name, e.g. "Bahrain International Airport"',
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
              'description': 'Song name, artist, album, or genre, e.g. "Lofi hip hop", "Drake"',
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
        'description':
            'Control a smart TV on the local WiFi network. '
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
        'description':
            'Break a complex request into sequential steps and execute them one by one. '
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
              'description': 'One-sentence summary of what this plan accomplishes',
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
                    'description': 'Arguments for the tool, if a tool is specified.',
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
        'description':
            'Delegate any software/coding job to Claude, the stronger coding brain: '
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
        'description':
            "Have Kai's two brains dialogue to refine an idea: GPT (the Muse) "
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
              'description': 'Absolute path to the repo/folder, or empty to disable.',
            },
          },
          'required': ['path'],
        },
      },
    },
  ];

  // ── Tool dispatch ─────────────────────────────────────────────────────────
  //
  // create_plan is intercepted upstream in _callOpenAIWithTools before
  // reaching this method — it never arrives here.

  Future<String> execute(String toolName, Map<String, dynamic> args) async {
    try {
      switch (toolName) {

        // ── Dart-side tools ────────────────────────────────────────────────

        case 'get_current_time':
          final now = DateTime.now().toLocal();
          final days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
          final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
          return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day} ${now.year} — '
              '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')} (Bahrain, UTC+3)';

        case 'web_search':
          final query = args['query'] as String? ?? '';
          if (query.isEmpty) return 'No query provided.';
          return await _googleSearch(query);

        case 'get_weather':
          final location = args['location'] as String? ?? 'Bahrain';
          return await _googleSearch('current weather $location today temperature');

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

        // ── Android-side tools (via KaiToolsPlugin) ────────────────────────

        case 'set_alarm':
          return await _invokeAndroid('setAlarm', {
            'hour':   args['hour'],
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
            'title':       args['title'],
            'date':        args['date'],
            'startTime':   args['start_time'],
            if (args['end_time']    != null) 'endTime':     args['end_time'],
            if (args['description'] != null) 'description': args['description'],
            if (args['location']    != null) 'location':    args['location'],
          });

        case 'open_app':
          return await _invokeAndroid('openApp', {'appName': args['app_name'] ?? ''});

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
          return await _invokeAndroid('callContact', {'contact': args['contact']});

        case 'navigate_to':
          return await _invokeAndroid('navigateTo', {'destination': args['destination']});

        case 'play_music':
          return await _invokeAndroid('playMusic', {'query': args['query'] ?? ''});

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
            action:   args['action']    as String? ?? 'power',
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
      return 'Tool "$toolName" encountered an error: $e';
    }
  }

  // ── Coding brain (Claude) ──────────────────────────────────────────────────
  // Hands a coding job to Claude Sonnet and returns its answer for GPT to relay.
  // Degrades gracefully when no Anthropic key is configured.
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
    final cseId  = await AIConfig.getGoogleCseId();
    if (apiKey.isEmpty || cseId.isEmpty) return 'Search unavailable: Google API keys not configured.';
    final resp = await GoogleSearchService().search(
      apiKey: apiKey,
      cseId:  cseId,
      query:  query,
      num:    5,
      dateRestrict: 'd3',
    );
    if (!resp.hasResults) return 'No results found for: $query';
    return GoogleSearchService.buildWebContext(resp.results);
  }

  Future<String> _invokeAndroid(String method, Map<String, dynamic> args) async {
    final result = await _channel.invokeMethod<dynamic>(method, args);
    if (result == null) return 'Done.';
    if (result is String) return result;
    return jsonEncode(result);
  }
}
