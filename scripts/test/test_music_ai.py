#!/usr/bin/env python3
"""Test the new AI music query generation logic"""

def analyze_prompt_test(prompt):
    """Test version of prompt analysis"""
    prompt_lower = prompt.lower()
    
    environments = {
        'haunted_mansion': ['haunted', 'ghost', 'mansion', 'creepy', 'eerie', 'spooky', 'whisper', 'spectral', 'paranormal'],
        'dungeon': ['dungeon', 'chamber', 'underground', 'crypt', 'tomb', 'cell', 'chains'],
        'forest': ['forest', 'woods', 'trees', 'jungle', 'grove', 'woodland', 'ancient forest'],
        'tavern': ['tavern', 'inn', 'bar', 'pub', 'alehouse', 'drinking hall', 'warm', 'cozy'],
        'cave': ['cave', 'cavern', 'grotto', 'stalactite', 'stalactites', 'caverns'],
        'castle': ['castle', 'fortress', 'keep', 'tower', 'throne room', 'royal', 'hall'],
        'battlefield': ['battlefield', 'war', 'combat', 'battle', 'skirmish', 'carnage'],
        'market': ['market', 'marketplace', 'bazaar', 'square', 'plaza', 'trading post', 'merchant']
    }
    
    actions = {
        'lightning': ['lightning', 'thunder', 'storm', 'electrical', 'shock', 'thunderbolt', 'lightning bolt'],
        'fireball': ['fireball', 'fire spell', 'flame burst', 'inferno', 'flames', 'burning'],
        'healing': ['healing', 'restore', 'cure', 'mend', 'life', 'revival', 'resurrection'],
        'magic': ['cast', 'spell', 'magic', 'enchant', 'arcane', 'magical', 'sorcery'],
        'combat': ['attack', 'fight', 'battle', 'strike', 'clash', 'duel', 'combat', 'swords']
    }
    
    moods = {
        'spooky': ['spooky', 'scary', 'frightening', 'creepy', 'horror', 'dread', 'ominous', 'eerie', 'sinister'],
        'epic': ['epic', 'heroic', 'legendary', 'grand', 'majestic', 'triumphant', 'destiny', 'glorious'],
        'peaceful': ['peaceful', 'calm', 'serene', 'tranquil', 'quiet', 'still', 'rest']
    }
    
    detected_env = 'abstract'
    detected_action = 'none'
    detected_mood = 'neutral'
    
    for env, keywords in environments.items():
        if any(kw in prompt_lower for kw in keywords):
            detected_env = env
            break
    
    if detected_env not in ['haunted_mansion']:
        for action, keywords in actions.items():
            if any(kw in prompt_lower for kw in keywords):
                detected_action = action
                break
    
    for mood, keywords in moods.items():
        if any(kw in prompt_lower for kw in keywords):
            detected_mood = mood
            break
    
    return {
        'environment': detected_env,
        'action': detected_action,
        'mood': detected_mood
    }


def generate_music_query_test(scene_data):
    """Test version of AI music query generation"""
    environment = scene_data['environment']
    action = scene_data['action']
    mood = scene_data['mood']
    
    query_parts = []
    
    action_music_map = {
        'fireball': ['epic', 'dramatic', 'intense', 'orchestral', 'battle'],
        'lightning': ['thunderstorm', 'epic', 'dramatic', 'weather'],
        'healing': ['peaceful', 'serene', 'healing', 'magical', 'glowing'],
        'magic': ['mystical', 'magical', 'mysterious', 'ethereal', 'spellcasting'],
        'combat': ['epic', 'battle', 'intense', 'orchestral', 'dramatic']
    }
    
    if action in action_music_map:
        query_parts.extend(action_music_map[action])
    
    environment_music_map = {
        'haunted_mansion': ['haunted', 'mansion', 'creepy', 'gothic', 'eerie', 'ghost'],
        'dungeon': ['dungeon', 'underground', 'dark', 'ancient'],
        'forest': ['forest', 'woods', 'nature', 'wilderness', 'natural'],
        'tavern': ['tavern', 'medieval', 'folk', 'inn', 'fantasy'],
        'cave': ['cave', 'cavern', 'underground', 'mysterious', 'ancient'],
        'castle': ['castle', 'royal', 'medieval', 'fortress', 'regal'],
        'battlefield': ['battlefield', 'war', 'combat', 'orchestral', 'intense'],
        'market': ['market', 'bustling', 'medieval', 'folk', 'lively', 'fantasy'],
        'abstract': []
    }
    
    if environment in environment_music_map and environment != 'abstract':
        env_terms = environment_music_map[environment][:2]
        query_parts.extend(env_terms)
    
    mood_music_map = {
        'spooky': ['dark', 'ominous', 'mysterious', 'eerie', 'suspenseful'],
        'epic': ['epic', 'heroic', 'grand', 'legendary', 'majestic'],
        'peaceful': ['peaceful', 'calm', 'serene', 'tranquil', 'soothing']
    }
    
    if mood in mood_music_map and mood != 'neutral':
        mood_terms = mood_music_map[mood][:1]
        query_parts.extend(mood_terms)
    
    query_parts.append('music')
    
    if not any(word in query_parts for word in ['ambient', 'orchestral', 'folk']):
        query_parts.append('ambient')
    
    seen = set()
    final_parts = []
    for part in query_parts:
        if part.lower() not in seen:
            seen.add(part.lower())
            final_parts.append(part)
    
    music_query = ' '.join(final_parts)
    
    if len(final_parts) < 3:
        music_query = f"{music_query} fantasy D&D"
    
    return music_query


# Test scenarios
test_prompts = [
    "Warm cozy tavern with medieval atmosphere",
    "Haunted mansion filled with ghostly whispers",
    "Intense thunderstorm with lightning and thunder",
    "Epic battle in the dungeon",
    "Peaceful healing magic in the castle",
    "Dark forest at night mysterious creatures",
    "Bustling marketplace with merchants"
]

print("🧠 AI MUSIC QUERY GENERATION TEST\n")
print("=" * 80)

for prompt in test_prompts:
    analysis = analyze_prompt_test(prompt)
    query = generate_music_query_test(analysis)
    
    print(f"\nPrompt: {prompt}")
    print(f"  Environment: {analysis['environment']}")
    print(f"  Action: {analysis['action']}")
    print(f"  Mood: {analysis['mood']}")
    print(f"  Generated Query: '{query}'")

print("\n" + "=" * 80)
print("\n✅ Test complete! All music queries generated successfully.")
