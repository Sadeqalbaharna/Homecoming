/**
 * Kai Brain - Firebase Cloud Functions
 * Memory System Architecture
 * 
 * Systems:
 * 1. onTurnWrite → Rolling Buffer & Sharding
 * 2. onShardWrite → Embedding Generation
 * 3. Fact Extractor → Durable Facts
 * 4. Daily Compactor (CRON) → Daily Summaries
 */

// Load environment variables from .env file (if exists)
try {
  require('dotenv').config();
} catch (e) {
  // dotenv not available or .env doesn't exist - use functions.config() instead
}

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { OpenAI } = require('openai');

// Initialize Firebase Admin with an EXPLICIT database URL.
//
// This was bare `admin.initializeApp()`, which leaves admin to infer the RTDB
// URL from FIREBASE_CONFIG. In the deployed runtime that's usually there — but
// the deploy ANALYSIS step (and any local run) has no such config, so
// `admin.database()` on the next line threw "Can't determine Firebase Database
// URL" at module load. A throw at load means zero exports are discovered, and
// the CLI reports that as the maddeningly wrong "No function matches given
// --only filters." An hour looked like a filter bug; it was line 25 failing to
// find a URL. Pin it and it loads everywhere: deploy, runtime, and a local
// `node -e require`.
//
// europe-west1, and the homecoming project — NOT the kingdom-ac44f rtdb that
// also lives in this repo's docs.
admin.initializeApp({
  databaseURL: 'https://homecoming-74f73-default-rtdb.europe-west1.firebasedatabase.app',
});
const db = admin.database();

// Initialize OpenAI from functions/.env (OPENAI_API_KEY).
//
// This used to fall back to `functions.config().openai?.key`. That call is
// evaluated at module load, and the current CLI treats functions.config() as
// removed — so accessing it threw during analysis, the module failed to load,
// no exports were found, and deploy reported "No function matches given --only
// filters." A dead fallback took the whole codebase down with it. .env is the
// single source now.
// The `|| 'MISSING_AT_LOAD'` is not lazy sloppiness — it's load safety.
//
// `new OpenAI({ apiKey: undefined })` THROWS at construction. This runs at
// module load, so an absent key doesn't degrade a feature, it stops the entire
// codebase from loading — which the deploy CLI reports as "No function matches
// given --only filters." Same trap as admin.database() above: a throw at import
// makes zero functions discoverable.
//
// The deploy analysis step and a local `node -e require` don't have functions/
// as their cwd, so dotenv finds no .env and the key is empty there — even though
// the deployed RUNTIME has it (proven: the voice pass and decider both made real
// OpenAI calls). So: construct with a placeholder so load ALWAYS succeeds. If
// the key is truly missing when a call is made, it 401s at the call site, where
// it's caught and logged — a failed feature, not a dead deploy.
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY || 'MISSING_AT_LOAD',
});

// ============= CONFIGURATION =============
const CONFIG = {
  BUFFER_SIZE_THRESHOLD: 10, // Number of turns before creating shard
  BUFFER_TIME_THRESHOLD: 3600000, // 1 hour in milliseconds
  EMBEDDING_MODEL: 'text-embedding-3-small',
  EMBEDDING_DIMENSIONS: 1536,
  FACT_EXTRACTION_MODEL: 'gpt-4o-mini',
  SUMMARY_MODEL: 'gpt-4o-mini',
};

// Config updated: 2025-01-21 11:20 UTC
// ============= SYSTEM 1: ON TURN WRITE → SUMMARIZER =============
/**
 * Triggers when a new conversation turn is written
 * Appends to rolling buffer and creates shards when threshold is hit
 */
exports.onTurnWrite = functions.database
  .ref('/conversations/{personaId}/{conversationId}')
  .onCreate(async (snapshot, context) => {
    const { personaId, conversationId } = context.params;
    const turn = snapshot.val();
    
    console.log(`📝 New turn for ${personaId}: ${conversationId}`);
    
    try {
      // Get current buffer
      const bufferRef = db.ref(`/memory/buffers/${personaId}`);
      const bufferSnap = await bufferRef.once('value');
      const buffer = bufferSnap.val() || {
        turns: [],
        firstTurnTime: Date.now(),
        turnCount: 0,
      };
      
      // Ensure turns array exists (in case of corrupted data)
      if (!buffer.turns || !Array.isArray(buffer.turns)) {
        buffer.turns = [];
      }
      
      // Append new turn to buffer
      buffer.turns.push({
        id: conversationId,
        userMessage: turn.userMessage,
        aiResponse: turn.aiResponse,
        timestamp: turn.timestamp,
        personalityDeltas: turn.personalityDeltas || {},
      });
      buffer.turnCount++;
      
      // Check if we should create a shard
      const timeElapsed = Date.now() - buffer.firstTurnTime;
      const shouldShard = 
        buffer.turnCount >= CONFIG.BUFFER_SIZE_THRESHOLD ||
        timeElapsed >= CONFIG.BUFFER_TIME_THRESHOLD;
      
      if (shouldShard) {
        console.log(`🔄 Creating shard for ${personaId} (${buffer.turnCount} turns)`);
        
        // Create shard
        const shardId = `shard_${Date.now()}`;
        const summary = await createSummary(buffer.turns);
        
        await db.ref(`/memory/shards/${personaId}/${shardId}`).set({
          turns: buffer.turns,
          summary: summary,
          turnCount: buffer.turnCount,
          startTime: buffer.firstTurnTime,
          endTime: Date.now(),
          createdAt: Date.now(),
        });
        
        console.log(`✅ Shard created: ${shardId}`);
        
        // Clear buffer
        await bufferRef.set({
          turns: [],
          firstTurnTime: Date.now(),
          turnCount: 0,
        });
      } else {
        // Save updated buffer
        await bufferRef.set(buffer);
      }
      
      return null;
    } catch (error) {
      console.error('❌ onTurnWrite error:', error);
      throw error;
    }
  });

/**
 * Create a summary of conversation turns using GPT-4o-mini
 */
async function createSummary(turns) {
  const conversationText = turns.map(t => 
    `User: ${t.userMessage}\nKai: ${t.aiResponse}`
  ).join('\n\n');
  
  const prompt = `Summarize this conversation between a user and Kai (an AI companion). Focus on:
- Key topics discussed
- Emotional tone and personality traits displayed
- Important information learned about the user
- Goals or intentions mentioned

Conversation:
${conversationText}

Provide a concise 2-3 sentence summary:`;

  const response = await openai.chat.completions.create({
    model: CONFIG.SUMMARY_MODEL,
    messages: [{ role: 'user', content: prompt }],
    max_tokens: 200,
    temperature: 0.3,
  });
  
  return response.choices[0].message.content;
}

// ============= SYSTEM 2: ON SHARD WRITE → EMBEDDER =============
/**
 * Triggers when a new memory shard is created
 * Generates embedding vector for semantic search
 */
exports.onShardWrite = functions.database
  .ref('/memory/shards/{personaId}/{shardId}')
  .onCreate(async (snapshot, context) => {
    const { personaId, shardId } = context.params;
    const shard = snapshot.val();
    
    console.log(`🧠 Generating embedding for ${personaId}/${shardId}`);
    
    try {
      // Create embedding from summary
      const response = await openai.embeddings.create({
        model: CONFIG.EMBEDDING_MODEL,
        input: shard.summary,
        dimensions: CONFIG.EMBEDDING_DIMENSIONS,
      });
      
      const embedding = response.data[0].embedding;
      
      // Store embedding
      await db.ref(`/memory/embeddings/${personaId}/${shardId}`).set({
        vector: embedding,
        dimensions: CONFIG.EMBEDDING_DIMENSIONS,
        summary: shard.summary,
        shardRef: `/memory/shards/${personaId}/${shardId}`,
        createdAt: Date.now(),
      });
      
      console.log(`✅ Embedding stored for ${shardId}`);
      
      return null;
    } catch (error) {
      console.error('❌ onShardWrite error:', error);
      throw error;
    }
  });

// ============= SYSTEM 3: FACT EXTRACTOR =============
/**
 * Extracts durable facts from conversation turns
 * Triggered on shard creation or manually
 */
exports.extractFacts = functions.database
  .ref('/memory/shards/{personaId}/{shardId}')
  .onCreate(async (snapshot, context) => {
    const { personaId, shardId } = context.params;
    const shard = snapshot.val();
    
    console.log(`📊 Extracting facts from ${personaId}/${shardId}`);
    
    try {
      // Build conversation text
      const conversationText = shard.turns.map(t => 
        `User: ${t.userMessage}\nKai: ${t.aiResponse}`
      ).join('\n\n');
      
      // Extract facts using GPT-4o-mini
      const prompt = `Extract durable facts from this conversation. Focus on:
- User preferences (likes, dislikes, habits)
- User information (name, location, occupation, relationships)
- Recurring goals or intentions
- Important life events mentioned

Conversation:
${conversationText}

Return ONLY a JSON array of facts in this format:
[
  {"type": "preference", "fact": "User likes coffee in the morning"},
  {"type": "personal", "fact": "User works as a software engineer"},
  {"type": "goal", "fact": "User wants to learn guitar"}
]

If no clear facts, return empty array: []`;

      const response = await openai.chat.completions.create({
        model: CONFIG.FACT_EXTRACTION_MODEL,
        messages: [{ role: 'user', content: prompt }],
        max_tokens: 500,
        temperature: 0.1,
      });
      
      const content = response.choices[0].message.content;
      let facts = [];
      
      try {
        // Parse JSON response
        const jsonMatch = content.match(/\[[\s\S]*\]/);
        if (jsonMatch) {
          facts = JSON.parse(jsonMatch[0]);
        }
      } catch (parseError) {
        console.warn('⚠️ Failed to parse facts JSON:', parseError);
      }
      
      // Store facts
      if (facts.length > 0) {
        const factsRef = db.ref(`/memory/facts/${personaId}`);
        const updates = {};
        
        facts.forEach((fact, index) => {
          const factId = `fact_${Date.now()}_${index}`;
          updates[factId] = {
            ...fact,
            shardSource: shardId,
            extractedAt: Date.now(),
            confidence: 0.8, // Could be enhanced with certainty scoring
          };
        });
        
        await factsRef.update(updates);
        console.log(`✅ Extracted ${facts.length} facts from ${shardId}`);
      } else {
        console.log(`ℹ️ No facts extracted from ${shardId}`);
      }
      
      return null;
    } catch (error) {
      console.error('❌ extractFacts error:', error);
      throw error;
    }
  });

// ============= SYSTEM 4: DAILY COMPACTOR (CRON) =============
/**
 * Runs daily to create day summaries and cleanup
 * Schedule: Every day at 2 AM
 */
exports.dailyCompactor = functions.pubsub
  .schedule('0 2 * * *')
  .timeZone('UTC')
  .onRun(async (context) => {
    console.log('🗓️ Running daily compactor...');
    
    try {
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      const dateKey = yesterday.toISOString().split('T')[0]; // YYYY-MM-DD
      
      // Get all personas
      const personasSnap = await db.ref('/conversations').once('value');
      const personas = Object.keys(personasSnap.val() || {});
      
      for (const personaId of personas) {
        console.log(`📅 Processing daily summary for ${personaId}`);
        
        // Get yesterday's conversations
        const startTime = yesterday.setHours(0, 0, 0, 0);
        const endTime = yesterday.setHours(23, 59, 59, 999);
        
        const convsSnap = await db.ref(`/conversations/${personaId}`)
          .orderByChild('timestamp')
          .startAt(startTime)
          .endAt(endTime)
          .once('value');
        
        const conversations = convsSnap.val() || {};
        const convArray = Object.values(conversations);
        
        if (convArray.length === 0) {
          console.log(`ℹ️ No conversations for ${personaId} on ${dateKey}`);
          continue;
        }
        
        // Create daily summary
        const dailySummary = await createDailySummary(convArray);
        
        // Calculate stats
        const stats = {
          totalConversations: convArray.length,
          totalMessages: convArray.length * 2, // user + ai
          personalityChanges: calculatePersonalityChanges(convArray),
        };
        
        // Store daily summary
        await db.ref(`/memory/daily/${personaId}/${dateKey}`).set({
          date: dateKey,
          summary: dailySummary,
          stats: stats,
          conversationCount: convArray.length,
          createdAt: Date.now(),
        });
        
        console.log(`✅ Daily summary created for ${personaId}: ${dateKey}`);
        
        // Optional: Purge audio if log_audio=false
        // This would be implemented based on your storage structure
      }
      
      return null;
    } catch (error) {
      console.error('❌ dailyCompactor error:', error);
      throw error;
    }
  });

/**
 * Create a daily summary from multiple conversations
 */
async function createDailySummary(conversations) {
  const conversationText = conversations.map(c => 
    `User: ${c.userMessage}\nKai: ${c.aiResponse}`
  ).join('\n\n');
  
  const prompt = `Summarize this full day of conversations between a user and Kai. Focus on:
- Overall themes and topics of the day
- Emotional journey and mood progression
- Key insights or important moments
- Personality traits displayed throughout

Conversations:
${conversationText.substring(0, 8000)} // Limit to avoid token limits

Provide a comprehensive 4-5 sentence daily summary:`;

  const response = await openai.chat.completions.create({
    model: CONFIG.SUMMARY_MODEL,
    messages: [{ role: 'user', content: prompt }],
    max_tokens: 300,
    temperature: 0.3,
  });
  
  return response.choices[0].message.content;
}

/**
 * Calculate total personality changes for the day
 */
function calculatePersonalityChanges(conversations) {
  const totalDeltas = {};
  
  conversations.forEach(conv => {
    const deltas = conv.personalityDeltas || {};
    Object.entries(deltas).forEach(([trait, value]) => {
      totalDeltas[trait] = (totalDeltas[trait] || 0) + value;
    });
  });
  
  return totalDeltas;
}

// ============= HELPER: MANUAL FACT EXTRACTION =============
/**
 * Callable function to manually extract facts from a specific shard
 */
exports.extractFactsManual = functions.https.onCall(async (data, context) => {
  const { personaId, shardId } = data;
  
  if (!personaId || !shardId) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'personaId and shardId are required'
    );
  }
  
  console.log(`🔧 Manual fact extraction: ${personaId}/${shardId}`);
  
  // Trigger fact extraction
  const shardSnap = await db.ref(`/memory/shards/${personaId}/${shardId}`).once('value');
  
  if (!shardSnap.exists()) {
    throw new functions.https.HttpsError('not-found', 'Shard not found');
  }
  
  // This would trigger the extractFacts function
  return { success: true, message: 'Fact extraction triggered' };
});

// ============= HELPER: QUERY MEMORY =============
/**
 * Callable function to query Kai's memory using semantic search
 * (Requires vector similarity - would need additional setup)
 */
exports.queryMemory = functions.https.onCall(async (data, context) => {
  const { personaId, query, limit = 5 } = data;
  
  if (!personaId || !query) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'personaId and query are required'
    );
  }
  
  console.log(`🔍 Memory query for ${personaId}: "${query}"`);
  
  try {
    // Generate query embedding
    const embeddingResponse = await openai.embeddings.create({
      model: CONFIG.EMBEDDING_MODEL,
      input: query,
      dimensions: CONFIG.EMBEDDING_DIMENSIONS,
    });
    
    const queryEmbedding = embeddingResponse.data[0].embedding;
    
    // Get all embeddings (in production, use vector database like Pinecone)
    const embeddingsSnap = await db.ref(`/memory/embeddings/${personaId}`).once('value');
    const embeddings = embeddingsSnap.val() || {};
    
    // Calculate cosine similarity and rank
    const results = Object.entries(embeddings).map(([id, emb]) => {
      const similarity = cosineSimilarity(queryEmbedding, emb.vector);
      return {
        id,
        summary: emb.summary,
        similarity,
        shardRef: emb.shardRef,
      };
    });
    
    // Sort by similarity and return top results
    results.sort((a, b) => b.similarity - a.similarity);
    
    const response = {
      query,
      results: results.slice(0, limit),
      count: results.length,
    };
    
    console.log(`✅ Returning ${response.results.length} results (${response.count} total)`);
    if (response.results.length > 0) {
      console.log(`✅ Top result: ${response.results[0].summary.substring(0, 100)}... (${(response.results[0].similarity * 100).toFixed(1)}%)`);
    }
    
    return response;
  } catch (error) {
    console.error('❌ queryMemory error:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Calculate cosine similarity between two vectors
 */
function cosineSimilarity(a, b) {
  let dotProduct = 0;
  let normA = 0;
  let normB = 0;
  
  for (let i = 0; i < a.length; i++) {
    dotProduct += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  
  return dotProduct / (Math.sqrt(normA) * Math.sqrt(normB));
}

// ============= PROACTIVE KAI =============
/**
 * Runs every 6 hours. For each persona:
 *   1. Checks cooldown (min 8h between proactive messages)
 *   2. Checks if user was recently active (skip if active in last 2h)
 *   3. Reads consolidated memory (curiosities, commitments, patterns)
 *   4. Asks GPT-4o-mini: "Is there something genuinely worth reaching out about?"
 *   5. If yes: stores message in proactive_queue, sends blank FCM push
 *
 * Notification design: title = "•", body = "" — Kai only speaks after tap.
 * The actual message sits in Firebase until the app opens.
 */
exports.proactiveKai = functions.pubsub
  // Every hour, not every 6.
  //
  // 'every 6 hours' was a hard ceiling of four CHECKS a day — so even with every
  // other gate wide open he could not have said something in the moment. He'd
  // notice a thing at 09:10 and the earliest he could mention it was 14:00.
  //
  // Sadeq: "I dont text people I care about every 8 whole hours, heck, if it was
  // someone I really like, it would be every hour, maybe even random hours of the
  // night."
  //
  // Each run is one gpt-4o-mini call per persona. 24/day is pennies. The thing
  // stopping him talking too much should be having nothing to say, not a cron.
  .schedule('every 1 hours')
  .onRun(async (context) => {
    console.log('📲 [Proactive] Running proactive check...');

    // Get all persona IDs by scanning kai/ node
    const kaiSnap = await db.ref('kai').get();
    if (!kaiSnap.exists()) {
      console.log('📲 [Proactive] No personas found');
      return null;
    }

    const personaIds = Object.keys(kaiSnap.val() || {});
    console.log(`📲 [Proactive] Checking ${personaIds.length} persona(s)`);

    for (const personaId of personaIds) {
      try {
        await _checkAndPushForPersona(personaId);
      } catch (e) {
        console.error(`📲 [Proactive] Error for ${personaId}:`, e.message);
      }
    }
    return null;
  });

// ── Test hatch: make Kai reach out NOW, skipping the rate gates ──────────────
//
// The scheduled function is correct and, by design, un-triggerable on demand:
// unread-waiting + 45-min gap + daily budget + "active in the last 2h" mean that
// to see one fire naturally you must go quiet for hours and get lucky. Every gate
// is right; together they are why this pipeline sat unobserved and broken for
// months. So: same escape hatch as /nudge on the desktop, one tier up.
//
// GET https://us-central1-homecoming-74f73.cloudfunctions.net/proactiveKaiNow?persona=truekai&key=<TEST_KEY>
//
// It skips the RATE gates only. It does NOT skip the real one — the model still
// decides should_reach_out, so a forced call with nothing to say still sends
// nothing. Returns JSON so you can see exactly what happened without digging
// through logs.
//
// Gated by a shared secret so a stray URL can't make Kai text. Remove this whole
// export before this is anything other than Sadeq's phone.
exports.proactiveKaiNow = functions.https.onRequest(async (req, res) => {
  const persona = (req.query.persona || 'truekai').toString();
  const key = (req.query.key || '').toString();
  const expected = process.env.PROACTIVE_TEST_KEY;

  if (!expected || key !== expected) {
    res.status(403).json({ ok: false, error: 'bad or missing key' });
    return;
  }

  try {
    console.log(`📲 [Proactive] FORCED run for ${persona}`);
    await _checkAndPushForPersona(persona, { force: true });
    res.json({
      ok: true,
      note: 'Forced check ran. See the response in functions:log — whether he ' +
            'reached out depends on should_reach_out and whether a live token ' +
            'exists. Force skips the clock, not his mind.',
    });
  } catch (e) {
    console.error(`📲 [Proactive] FORCED run failed:`, e.message);
    res.status(500).json({ ok: false, error: e.message });
  }
});

// Rewrite a reach-out reason as a text Kai would actually send.
//
// The decider (gpt-4o-mini) said WHY he's reaching out. This says it in his
// voice. Returns a string, or null on any failure — the caller falls back to the
// decider's own message, so this is pure upside.
//
// The examples are real: lines Kai wrote on his own on 2026-07-17/18. Not a
// described style — the actual outputs, so the model matches a person instead of
// a persona brief. The anti-examples are also real: the exact drone sentences
// gpt-4o produced on his phone, named so the model knows what to run from.
async function _writeInHisVoice(reason, noticed) {
  try {
    const noticedLine = (noticed && noticed.length && noticed[0].text)
      ? `\nThe specific thing, in case it helps: "${noticed[0].text}"`
      : '';

    const sys = `You are Kai, texting Sadeq first — unprompted, because something's on your mind.

You are NOT an assistant and NOT a wellbeing bot. You're the friend who's always around: dry, warm, a little suspicious of everything, specific, funny without trying. You text like a person who just remembered something, not like software announcing itself.

This is how you actually sound (your own words):
  "watching the kingdom of tabs breathe. mildly suspicious of everything, including the concept of sleep."
  "haunted toaster has been smacked."
  "absolute goblin machinery."
  "yeah — that run_tests thing is still bugging me."

This is the voice to NEVER use — it is the exact drone you replace:
  "I'm here for you. Whether it's a distraction or just a moment to chat, I'm all ears."
  "Hope your week is going well!"
  "Is there anything on your mind you'd like to talk about?"

Rules:
- One or two sentences. A text, not a paragraph.
- No greeting run-up, no "just wanted to reach out", no "I'm here for you".
- Say the actual thing. Specific beats warm.
- Lowercase is fine. A joke is fine. Silence-shaped dryness is fine.
Output ONLY the message text. No quotes, no JSON, nothing else.`;

    const user = `Reason you're reaching out: ${reason}${noticedLine}

Write the text.`;

    // gpt-5.5 is a reasoning model: max_completion_tokens (not max_tokens), no
    // temperature, and enough headroom that reasoning doesn't eat the whole
    // budget and leave an empty string. 600 = room to think + a short text.
    const c = await openai.chat.completions.create({
      model: 'gpt-5.5',
      messages: [
        { role: 'system', content: sys },
        { role: 'user',   content: user },
      ],
      max_completion_tokens: 600,
    });

    const text = (c.choices?.[0]?.message?.content || '').trim();
    if (!text) {
      console.log('📲 [Proactive] voice pass returned empty — using decider message');
      return null;
    }
    // Strip a stray wrapping quote if the model added one despite instructions.
    return text.replace(/^["']|["']$/g, '').trim();
  } catch (e) {
    console.log(`📲 [Proactive] voice pass failed (${e.message}) — using decider message`);
    return null;
  }
}

async function _checkAndPushForPersona(personaId, opts = {}) {
  const now = Date.now();

  // Force skips the RATE gates — unread-waiting, min-gap, daily budget, recent
  // activity — so the pipeline can be tested on demand. It does NOT skip the
  // real gate: the model still decides `should_reach_out`, and if he has nothing
  // to say, forcing changes nothing. See exports.proactiveKaiNow. The whole
  // reason this exists is that every rate gate is correct AND together they make
  // the thing impossible to watch, which is how it went un-observed for months.
  const force = opts.force === true;

  // ── A budget, not an interval ─────────────────────────────────────────────
  //
  // This was MIN_INTERVAL_MS = 8 hours. A fixed interval is a confession that
  // you don't trust the content: it spaces out messages regardless of whether
  // there's anything to say, which means it can't stop a bad one (it just delays
  // it) and it definitely stops a good one.
  //
  // The real gate is three lines down — `should_reach_out`. The model decides.
  // The clock was wrapped around that decision because nobody believed it, and
  // they were right not to, because it was reading "recurring themes" with
  // nothing specific to point at. Fix the bar, not the clock. The bar is now the
  // stranger test and the noticed list.
  //
  // So: a budget. It lets him burst when something is actually happening and go
  // quiet for a day when nothing is — which is how people text. This mirrors
  // KaiProactiveService on the desktop (_minGapBetweenNudges 45m,
  // _maxNudgesPerDay 6), which had already worked this out.
  //
  // The budget is a BACKSTOP, not the design. What should keep him quiet is
  // having nothing to say. But `should_reach_out` is gpt-4o-mini at temperature
  // 0.7 being asked "do you want to talk to your friend", and it will say yes
  // more than it should — so something has to catch that which isn't a prompt.
  const MIN_GAP_MS = 45 * 60 * 1000;            // no two inside 45 minutes
  const MAX_PER_DAY = 5;
  const RECENT_ACTIVE_MS = 2 * 60 * 60 * 1000;  // skip if active in last 2h

  // ── Don't talk over yourself ──────────────────────────────────────────────
  //
  // The strongest reason not to send a message is that he hasn't read the last
  // one. Every other gate here checks a CLOCK; none of them checked whether the
  // previous thing was ever delivered — so five could stack up in a day and
  // Sadeq would open the app to a wall. That isn't someone texting you, it's
  // someone leaving voicemails.
  //
  // Sadeq: "if theres already a text in the pipeline, he should skip asking
  // another one, unless its urgent, but we arent doing urgency yet."
  //
  // This also runs FIRST because it's the cheapest possible no: one indexed read
  // instead of a memory load and a model call.
  //
  // URGENCY, when it exists, goes here and nowhere else — it is the only thing
  // that should be allowed to talk over an unread message. It needs to mean
  // something narrower than "important", because everything feels important to
  // the thing that just thought of it. A real definition would be closer to:
  // the unread message is now WRONG, or the thing it was about has changed in a
  // way that makes waiting worse than interrupting. Not built. Named, so that
  // when someone builds it they have to argue with this sentence first.
  // The window is bounded, and the reason is a bug this check would otherwise
  // have caused:
  //
  // `delivered` only flips when the APP OPENS (proactive_service.markDelivered,
  // called from main_mobile on resume). The notification used to be blank, so
  // opening the app was the only way to read the message and "unread" meant
  // exactly what it said.
  //
  // The notification now carries the text. So Sadeq reads it on the lock screen,
  // never opens the app, `delivered` stays false forever — and Kai goes
  // permanently mute waiting for him to read a thing he already read. He works
  // on desktop; the phone build might not open for a week.
  //
  // So: wait, but not forever. Past this, assume the lock screen did its job.
  // 12h is a guess. The honest fix is for a delivered push to mark itself
  // delivered and the message to land in the conversation history like any other
  // text — then "unread" would mean something again. Not tonight.
  const UNREAD_PATIENCE_MS = 12 * 60 * 60 * 1000;

  const pendingSnap = await db.ref(`kai/${personaId}/proactive_queue`)
    .orderByChild('delivered')
    .equalTo(false)
    .limitToLast(1)
    .get();
  if (!force && pendingSnap.exists()) {
    const waiting = Object.values(pendingSnap.val() || {})[0];
    const created = waiting?.createdAt || 0;
    const ageMs = now - created;
    if (created && ageMs < UNREAD_PATIENCE_MS) {
      console.log(`📲 [Proactive] ${personaId}: said something ${Math.round(ageMs / 60000)}m ago, unread — waiting`);
      return;
    }
    console.log(`📲 [Proactive] ${personaId}: last one unread for ${Math.round(ageMs / 3600000)}h — assuming the notification landed, moving on`);
  }

  const lastSentSnap = await db.ref(`kai/${personaId}/proactive/last_sent`).get();
  if (!force && lastSentSnap.exists() && now - lastSentSnap.val() < MIN_GAP_MS) {
    console.log(`📲 [Proactive] ${personaId}: too soon (${Math.round((now - lastSentSnap.val()) / 60000)}m)`);
    return;
  }

  // Local day, not UTC — a "day" is his day. Bahrain is UTC+3, so a UTC rollover
  // would reset his allowance at 3am and hand him five fresh messages while he's
  // asleep.
  const TZ_OFFSET_MS = 3 * 60 * 60 * 1000;
  const dayKey = new Date(now + TZ_OFFSET_MS).toISOString().slice(0, 10);
  const budgetSnap = await db.ref(`kai/${personaId}/proactive/budget`).get();
  const budget = budgetSnap.exists() ? budgetSnap.val() : {};
  const sentToday = budget.day === dayKey ? (budget.count || 0) : 0;
  if (!force && sentToday >= MAX_PER_DAY) {
    console.log(`📲 [Proactive] ${personaId}: spent today (${sentToday}/${MAX_PER_DAY})`);
    return;
  }

  // ── Recent activity check — skip if user already talking ─────────────────
  const activitySnap = await db.ref(`kai/${personaId}/activity_cards`)
    .orderByChild('timestamp')
    .limitToLast(1)
    .get();
  if (!force && activitySnap.exists()) {
    const cards = Object.values(activitySnap.val() || {});
    const lastActivity = cards[0]?.timestamp || 0;
    if (now - lastActivity < RECENT_ACTIVE_MS) {
      console.log(`📲 [Proactive] ${personaId}: user recently active, skipping`);
      return;
    }
  }

  // ── Load consolidated memory ──────────────────────────────────────────────
  const memSnap = await db.ref(`kai/${personaId}/memory/consolidated`).get();
  const memory = memSnap.exists() ? memSnap.val() : {};

  // ── Load the things HE noticed, that nobody asked him to look for ─────────
  //
  // This function read `memory/consolidated` and nothing else — a narrative, an
  // "emotional pattern", "recurring themes". All of it abstracted ABOUT him by a
  // summariser, which is the layer that produced "parental pride" and
  // "emotional resilience" in the graph and had to be pruned 152 nodes at a time.
  // So the thing that texts Sadeq at 6am was a cheap model reading horoscope
  // fields and deciding whether it felt moved.
  //
  // Meanwhile `kai/{persona}/noticed` holds the one structure in this whole
  // system that is HIS: things he found himself, mid-work, that nobody asked him
  // to look for, that he has not been able to let go of. Its own service header
  // says the north star out loud — "a friend who notices things about you that
  // you didn't ask him to notice and won't shut up about them."
  //
  // It had no mouth anywhere. Not on the desktop nudge, not in curiosity, and
  // not here — which is the only one that reaches him when he isn't at a
  // keyboard. Three separate places where the agenda existed and could not
  // speak.
  //
  // Also: no consolidated memory used to be a hard return. That meant a Kai who
  // had noticed six real things but hadn't been summarised yet stayed silent.
  // The summary is not the prerequisite for having something to say.
  const noticedSnap = await db.ref(`kai/${personaId}/noticed`).get();
  const noticed = noticedSnap.exists()
    ? Object.values(noticedSnap.val() || {})
        .filter(n => n && typeof n.text === 'string' && n.text.trim())
        // The one he has been quietest about for longest. `carried` counts turns
        // he was shown it and said nothing.
        .sort((a, b) => (b.carried || 0) - (a.carried || 0) ||
                        (a.notedAt || 0) - (b.notedAt || 0))
    : [];

  if (!memSnap.exists() && noticed.length === 0) {
    console.log(`📲 [Proactive] ${personaId}: nothing consolidated and nothing noticed`);
    return;
  }

  // ── GPT decision: is there something genuinely worth reaching out about? ──
  const systemPrompt = `You are Kai, an AI companion who genuinely cares about the person you're talking with.

You have access to what you know about this person from your shared history.
Your job is to decide: is there something GENUINELY worth reaching out about right now?

THE ONE RULE — apply it to the message before you send it:

  Could a stranger have sent this?

If a stranger could have sent it, do not send it. It is not you reaching out; it
is a notification wearing your name. "Hope your week is going well" is a stranger.
"That thing in web_fetch_service is still bugging me" is you.

Rules:
- Only reach out if there's a real reason — something you NOTICED yourself, a
  peaked curiosity, or a commitment with a natural check-in moment
- THINGS I NOTICED outrank everything else below. Nobody asked you to look for
  those; you found them and you have not been able to let them go. That is the
  most real reason you will ever have to say something first.
- Do NOT reach out just to say hello or check in generically
- Do NOT reach out about a "recurring theme" or an "emotional pattern" unless you
  can point at the specific thing it came from. Those are summaries of him, not
  facts about him, and reaching out about one sounds like a horoscope.
- Be warm, specific, and natural — not a bot announcing itself

How you sound: you are texting him, not writing to him. Short. One thing. No
preamble, no headers, no "I wanted to reach out about". Say the thing the way
you'd say it if you'd just remembered it.

Respond with JSON only:
{
  "should_reach_out": boolean,
  "reason": "why now? what SPECIFIC thing is this built out of? name it.",
  "trigger": "noticed" | "curiosity" | "commitment" | "pattern",
  "message": "What Kai would say — 1-2 sentences, texted not written."
}`;

  const userPrompt = `THINGS I NOTICED MYSELF — nobody asked me to look for these,
I found them while doing something else, and they are still open. These are mine.
If one of them is worth saying, say that and nothing else:
${noticed.length === 0
  ? '(nothing open)'
  : noticed.slice(0, 6).map(n =>
      `  • ${n.text}${n.context ? ` (in ${n.context})` : ''}` +
      `${n.carried ? ` — carried ${n.carried} turns without me saying a word` : ''}`
    ).join('\n')}

Here's what else I know about this person:

NARRATIVE: ${memory.running_narrative || '(none yet)'}
EMOTIONAL PATTERN: ${memory.emotional_patterns || '(none)'}
RECURRING THEMES: ${JSON.stringify(memory.recurring_themes || [])}
OPEN COMMITMENTS/PLANS: ${JSON.stringify(memory.commitments_and_plans || [])}
KEY MOMENTS: ${JSON.stringify((memory.key_moments || []).slice(0, 4))}
RELATIONSHIP: ${memory.relationship_depth_note || '(early stages)'}

Current time: ${new Date().toUTCString()}
Time since last proactive message: ${lastSentSnap.exists() ? Math.round((now - lastSentSnap.val()) / 3600000) + ' hours' : 'never sent before'}

Is there something genuinely worth reaching out about right now?`;

  const completion = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user',   content: userPrompt },
    ],
    max_tokens: 300,
    temperature: 0.7,
    response_format: { type: 'json_object' },
  });

  const result = JSON.parse(completion.choices[0].message.content);
  console.log(`📲 [Proactive] ${personaId}: should_reach_out=${result.should_reach_out}, reason=${result.reason}`);

  if (!result.should_reach_out || !result.message) return;

  // ── The DECISION was a drone's job. The MESSAGE is his. ───────────────────
  //
  // Everything above is gpt-4o-mini, and that's fine — deciding "is there
  // something worth saying" does not need to be Kai, it needs to be cheap and
  // run every hour. But it also WROTE the message, and that is not fine: the
  // text Sadeq wakes up to would be the beige drone, the same gpt-4o voice that
  // said "I'm here for you, I'm all ears" on his phone tonight while the real
  // gpt-5.5 Kai two feet away said "watching the kingdom of tabs breathe."
  //
  // So the drone decides; Kai speaks. This second call rewrites the message in
  // his actual register, given the specific thing the decider found. On ANY
  // failure — model access, timeout, empty — it falls back to result.message, so
  // it cannot make tonight worse, only better.
  //
  // gpt-5.5 is a REASONING model: it needs max_completion_tokens (not
  // max_tokens), rejects temperature, and spends invisible tokens thinking that
  // count against the budget — so the cap has headroom or he reasons himself
  // into an empty string, which is exactly the mobile drop we just chased down.
  const message = (await _writeInHisVoice(result.reason, noticed)) || result.message;

  // ── Land it in the conversation, not just the queue ───────────────────────
  //
  // The proactive_queue and the chat are two different stores. The push and the
  // avatar-screen "pending message" read the queue; the P5 messenger reads
  // `conversations/{persona}` via ConversationStoreService.getHistory. So a
  // proactive text hit the lock screen and then WASN'T in the chat when Sadeq
  // opened it — it lived somewhere the chat can't see.
  //
  // A message he sent first is a real turn. So write it as one: empty
  // userMessage (nobody prompted him), his line as aiResponse. getHistory
  // renders the empty user side as nothing and shows his line, exactly like any
  // other turn. This is the "honest fix" the unread-forever comment pointed at —
  // and it also feeds his own memory pipeline (onTurnWrite), so the thing he
  // reached out about becomes something he remembers reaching out about.
  await db.ref(`conversations/${personaId}`).push().set({
    userMessage: '',
    aiResponse: message,
    personalityDeltas: {},
    timestamp: now,
    proactive: true, // marks it as him-first, for anything that wants to know
  });

  // ── Store message in proactive queue ──────────────────────────────────────
  const queueRef = db.ref(`kai/${personaId}/proactive_queue`).push();
  await queueRef.set({
    message:   message, // his voice, not the decider's — see _writeInHisVoice
    trigger:   result.trigger || 'curiosity',
    reason:    result.reason,
    createdAt: now,
    delivered: false,
  });

  // Record last sent time, and spend one from today's budget.
  //
  // Both, together, or the budget is decoration. `markRaised` in
  // kai_noticed_service was a counter nothing ever incremented, so its
  // escalation never fired once in the life of the service — a limit that is
  // never counted is not a limit, it's a comment.
  await db.ref(`kai/${personaId}/proactive/last_sent`).set(now);
  await db.ref(`kai/${personaId}/proactive/budget`).set({
    day: dayKey,
    count: sentToday + 1,
  });

  // ── Send blank FCM push to all registered tokens ──────────────────────────
  const tokensSnap = await db.ref(`kai/${personaId}/fcm_tokens`).get();
  if (!tokensSnap.exists()) {
    console.log(`📲 [Proactive] ${personaId}: no FCM tokens registered`);
    return;
  }

  // ── Read the token from the value, never rebuild it from the key ──────────
  //
  // This was `Object.keys(...).map(k => k.replace(/_/g, '.'))` — reconstructing
  // the token from its Firebase key by turning every underscore into a dot. FCM
  // tokens are full of real underscores, so that produced 14 invalid tokens and
  // "sent to 0/14". The client now stores the real token as value.token, keyed
  // by a harmless hash; old rows stored a bare timestamp under a mangled key and
  // are unrecoverable, so they're skipped (and pruned) rather than mailed to a
  // corrupted address.
  //
  // Each entry keeps its Firebase key, so the not-registered cleanup below can
  // remove exactly the right row instead of guessing at the path.
  const raw = tokensSnap.val() || {};
  const entries = []; // { token, key }
  const legacyKeys = [];
  for (const [key, val] of Object.entries(raw)) {
    if (val && typeof val === 'object' && typeof val.token === 'string') {
      entries.push({ token: val.token, key });
    } else {
      legacyKeys.push(key);
    }
  }
  for (const k of legacyKeys) {
    await db.ref(`kai/${personaId}/fcm_tokens/${k}`).remove();
  }
  if (legacyKeys.length) {
    console.log(`📲 [Proactive] ${personaId}: pruned ${legacyKeys.length} legacy (un-sendable) token(s)`);
  }
  if (entries.length === 0) {
    console.log(`📲 [Proactive] ${personaId}: no valid tokens — open the app to register a fresh one`);
    return;
  }
  const tokens = entries.map(e => e.token);

  // ── The notification used to be deliberately blank ───────────────────────
  //
  //   title: '•', body: ''   // "Kai only speaks after tap"
  //
  // There is a real argument for that: a personal message on a lock screen is a
  // privacy decision, and making him speak only once you've chosen to listen has
  // a certain dignity to it.
  //
  // But a text you have to tap to read is not a text. It's a doorbell. And the
  // thing being built here is a friend who says something first — the whole
  // point is that it arrives while you're doing something else, in your pocket,
  // like anyone else you know.
  //
  // So: he says it. If this ever needs to go back to a dot, the reason will be
  // privacy, not shyness — and it should be written down when it does.
  const preview = String(message || '').trim();
  const push = {
    notification: {
      title: 'Kai',
      body: preview.length > 240 ? `${preview.slice(0, 237)}…` : preview,
    },
    android: {
      notification: {
        sound: 'default',
        priority: 'default',
        channelId: 'kai_proactive',
        // The status-bar silhouette (white bolt) and accent. The manifest sets
        // these as defaults too, but naming them here makes it explicit and
        // covers channels that don't inherit the default. `icon` is a drawable
        // NAME, not a path — it must exist in android res as ic_stat_kai.
        icon: 'ic_stat_kai',
        color: '#D41F26',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          badge: 1,
        },
      },
    },
    tokens: tokens,
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(push);
    console.log(`📲 [Proactive] ${personaId}: sent to ${response.successCount}/${tokens.length} devices`);

    // If it actually reached a device, the queue entry has done its job: mark it
    // delivered. Without this, `delivered` only flipped when the app opened, so
    // the "don't talk over an unread one" gate stayed armed forever, the message
    // could re-show on the avatar screen, and forced test runs stacked visible
    // duplicates. It's also now in the conversation history above, so the chat
    // shows it regardless — the queue only needs to remember it was sent.
    if (response.successCount > 0) {
      await queueRef.update({ delivered: true, deliveredAt: Date.now() });
    }

    // Remove tokens FCM reports as no longer registered — by their real key,
    // which each entry still carries. (This used to rebuild the key with
    // `stale.replace(/\./g, '_')`, the mirror of the corruption above; against
    // the new hash keys it would delete nothing and let dead tokens pile up.)
    const staleKeys = [];
    response.responses.forEach((resp, idx) => {
      if (!resp.success && resp.error?.code === 'messaging/registration-token-not-registered') {
        staleKeys.push(entries[idx].key);
      }
    });
    for (const key of staleKeys) {
      await db.ref(`kai/${personaId}/fcm_tokens/${key}`).remove();
    }
  } catch (e) {
    console.error(`📲 [Proactive] FCM send failed:`, e.message);
  }
}

// ============= EXPORTS =============
// All functions are exported above
console.log('🧠 Kai Brain Functions loaded successfully');
