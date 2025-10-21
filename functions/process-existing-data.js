/**
 * Manual Memory Formation Script
 * 
 * This script processes existing conversations in Firebase
 * and creates memory shards + embeddings retroactively.
 * 
 * Run this ONCE to process all historical data.
 */

const admin = require('firebase-admin');
const { OpenAI } = require('openai');
require('dotenv').config();

// Initialize Firebase Admin
const serviceAccount = require('./serviceAccountKey.json'); // You'll need to download this

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  databaseURL: 'https://your-project-id.firebaseio.com' // Update with your project ID
});

const db = admin.database();

// Initialize OpenAI
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

const CONFIG = {
  BUFFER_SIZE_THRESHOLD: 10,
  EMBEDDING_MODEL: 'text-embedding-3-small',
  EMBEDDING_DIMENSIONS: 1536,
};

/**
 * Process existing conversations for a persona
 */
async function processExistingConversations(personaId) {
  console.log(`\n🔍 Processing conversations for: ${personaId}`);
  
  try {
    // Get all conversations
    const conversationsSnap = await db.ref(`/conversations/${personaId}`).once('value');
    const conversations = conversationsSnap.val();
    
    if (!conversations) {
      console.log(`⚠️ No conversations found for ${personaId}`);
      return;
    }
    
    // Convert to array and sort by timestamp
    const conversationArray = Object.entries(conversations).map(([id, conv]) => ({
      id,
      ...conv,
    })).sort((a, b) => a.timestamp - b.timestamp);
    
    console.log(`📊 Found ${conversationArray.length} conversations`);
    
    // Create shards from groups of conversations
    const shards = [];
    for (let i = 0; i < conversationArray.length; i += CONFIG.BUFFER_SIZE_THRESHOLD) {
      const chunk = conversationArray.slice(i, i + CONFIG.BUFFER_SIZE_THRESHOLD);
      
      if (chunk.length >= CONFIG.BUFFER_SIZE_THRESHOLD) {
        shards.push(chunk);
      }
    }
    
    console.log(`📦 Creating ${shards.length} memory shards...`);
    
    // Process each shard
    for (let i = 0; i < shards.length; i++) {
      const turns = shards[i];
      const shardId = `shard_${Date.now()}_${i}`;
      
      console.log(`\n  Processing shard ${i + 1}/${shards.length} (${turns.length} turns)`);
      
      // Generate summary
      const summary = await generateSummary(turns);
      console.log(`  ✅ Summary: ${summary.substring(0, 100)}...`);
      
      // Save shard
      await db.ref(`/memory/shards/${personaId}/${shardId}`).set({
        turns: turns.map(t => ({
          userMessage: t.userMessage,
          aiResponse: t.aiResponse,
          timestamp: t.timestamp,
        })),
        summary,
        createdAt: Date.now(),
        turnCount: turns.length,
      });
      
      console.log(`  ✅ Shard saved`);
      
      // Generate embedding
      const response = await openai.embeddings.create({
        model: CONFIG.EMBEDDING_MODEL,
        input: summary,
        dimensions: CONFIG.EMBEDDING_DIMENSIONS,
      });
      
      const embedding = response.data[0].embedding;
      
      // Save embedding
      await db.ref(`/memory/embeddings/${personaId}/${shardId}`).set({
        vector: embedding,
        dimensions: CONFIG.EMBEDDING_DIMENSIONS,
        summary,
        shardRef: `/memory/shards/${personaId}/${shardId}`,
        createdAt: Date.now(),
      });
      
      console.log(`  ✅ Embedding generated and saved`);
      
      // Small delay to avoid rate limits
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
    
    console.log(`\n✅ Successfully processed ${shards.length} shards for ${personaId}`);
    
  } catch (error) {
    console.error(`❌ Error processing ${personaId}:`, error);
    throw error;
  }
}

/**
 * Generate summary using GPT
 */
async function generateSummary(turns) {
  const conversationText = turns.map((turn, i) => 
    `Turn ${i + 1}:\nUser: ${turn.userMessage}\nKai: ${turn.aiResponse}`
  ).join('\n\n');
  
  const prompt = `Summarize the key points from this conversation between a user and Kai (an AI companion). Focus on:
- Facts about the user
- Topics discussed
- User's interests and preferences
- Important details mentioned

Conversation:
${conversationText}

Summary (2-3 sentences):`;

  const response = await openai.chat.completions.create({
    model: 'gpt-4o-mini',
    messages: [{ role: 'user', content: prompt }],
    max_tokens: 150,
    temperature: 0.5,
  });
  
  return response.choices[0].message.content.trim();
}

/**
 * Calculate cosine similarity
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

// ============= RUN SCRIPT =============

async function main() {
  console.log('🧠 Kai Brain - Manual Memory Formation');
  console.log('=====================================\n');
  
  const personaId = 'truekai'; // Change if needed
  
  try {
    await processExistingConversations(personaId);
    
    console.log('\n✅ Script completed successfully!');
    console.log('\nMemory shards and embeddings have been created.');
    console.log('You can now query memories in the app!');
    
  } catch (error) {
    console.error('\n❌ Script failed:', error);
    process.exit(1);
  }
  
  process.exit(0);
}

// Run if executed directly
if (require.main === module) {
  main();
}

module.exports = { processExistingConversations };
