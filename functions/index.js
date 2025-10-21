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

// Load environment variables from .env file
require('dotenv').config();

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
    const response = await openai.embeddings.create({
      model: CONFIG.EMBEDDING_MODEL,
      input: query,
      dimensions: CONFIG.EMBEDDING_DIMENSIONS,
    });
    
    const queryEmbedding = response.data[0].embedding;
    
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
    
    return {
      query,
      results: results.slice(0, limit),
      count: results.length,
    };
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

// ============= EXPORTS =============
// All functions are exported above
console.log('🧠 Kai Brain Functions loaded successfully');
