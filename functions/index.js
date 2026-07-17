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

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.database();

// Initialize OpenAI (using environment variable set during deployment)
// Priority: 1) .env file (process.env), 2) functions.config() (deprecated)
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY || functions.config().openai?.key,
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

async function _checkAndPushForPersona(personaId) {
  const now = Date.now();

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
  if (pendingSnap.exists()) {
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
  if (lastSentSnap.exists() && now - lastSentSnap.val() < MIN_GAP_MS) {
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
  if (sentToday >= MAX_PER_DAY) {
    console.log(`📲 [Proactive] ${personaId}: spent today (${sentToday}/${MAX_PER_DAY})`);
    return;
  }

  // ── Recent activity check — skip if user already talking ─────────────────
  const activitySnap = await db.ref(`kai/${personaId}/activity_cards`)
    .orderByChild('timestamp')
    .limitToLast(1)
    .get();
  if (activitySnap.exists()) {
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

  // ── Store message in proactive queue ──────────────────────────────────────
  const queueRef = db.ref(`kai/${personaId}/proactive_queue`).push();
  await queueRef.set({
    message:   result.message,
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

  const tokens = Object.keys(tokensSnap.val() || {})
    .map(k => k.replace(/_/g, '.'));  // un-sanitize dots

  if (tokens.length === 0) return;

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
  const preview = String(result.message || '').trim();
  const message = {
    notification: {
      title: 'Kai',
      body: preview.length > 240 ? `${preview.slice(0, 237)}…` : preview,
    },
    android: {
      notification: {
        sound: 'default',
        priority: 'default',
        channelId: 'kai_proactive',
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
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(`📲 [Proactive] ${personaId}: sent to ${response.successCount}/${tokens.length} devices`);

    // Remove stale tokens (404 = token no longer valid)
    const staleTokens = [];
    response.responses.forEach((resp, idx) => {
      if (!resp.success && resp.error?.code === 'messaging/registration-token-not-registered') {
        staleTokens.push(tokens[idx]);
      }
    });
    for (const stale of staleTokens) {
      const key = stale.replace(/\./g, '_');
      await db.ref(`kai/${personaId}/fcm_tokens/${key}`).remove();
    }
  } catch (e) {
    console.error(`📲 [Proactive] FCM send failed:`, e.message);
  }
}

// ============= EXPORTS =============
// All functions are exported above
console.log('🧠 Kai Brain Functions loaded successfully');
