#!/usr/bin/env python3
"""
seed_menu.py — Populates kingdom-ac44f RTDB /menu from the Tavern menu data.

Run once (or re-run to update):
    python3 seed_menu.py

Uses serviceAccountKey.json for kingdom-ac44f (same directory).
Skips items that already exist (matched by name) unless --force is passed.
    python3 seed_menu.py --force
"""

import os
import re
import sys
import time
import firebase_admin
from firebase_admin import credentials, db

# ── Init ──────────────────────────────────────────────────────────────────────

RTDB_URL        = 'https://kingdom-ac44f-default-rtdb.europe-west1.firebasedatabase.app'
SERVICE_ACCOUNT = os.path.join(os.path.dirname(__file__), 'serviceAccountKey.json')

if not firebase_admin._apps:
    firebase_admin.initialize_app(
        credentials.Certificate(SERVICE_ACCOUNT),
        {'databaseURL': RTDB_URL},
    )

FORCE = '--force' in sys.argv


def _key(name: str) -> str:
    """RTDB keys can't contain . # $ [ ] /  — replace with _"""
    return re.sub(r'[.#$\[\]/]', '_', name)

# ── Menu data ─────────────────────────────────────────────────────────────────
# Fields: name, category, price (BHD), description, allergens[], isVegetarian,
#         isVegan, canBeVegan, isGlutenFree, isNew, isBestSeller, isAvailable,
#         imageUrl (filled via dashboard), kaiNotes, sortOrder

MENU = [

    # ══════════════════════════════════════════════════════════════════════════
    # TO SHARE
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Bowl of Nuts',
        'category': 'To Share',
        'price': 3.5,
        'description': 'A generous bowl of mixed nuts.',
        'allergens': ['nuts'],
        'isVegetarian': True, 'isVegan': True, 'isGlutenFree': True,
        'isBestSeller': True,
        'kaiNotes': 'Popular bar snack. Strictly for nut-safe guests only.',
        'sortOrder': 1,
    },
    {
        'name': 'Elf Ears',
        'category': 'To Share',
        'price': 5.0,
        'description': 'Buttery zaatar crunch palmiers with pesto dip.',
        'allergens': ['gluten', 'dairy', 'sesame', 'nuts'],
        'isVegetarian': True,
        'kaiNotes': 'Zaatar contains sesame. Pesto contains pine nuts.',
        'sortOrder': 2,
    },
    {
        'name': 'Nibbles & Giggles',
        'category': 'To Share',
        'price': 5.0,
        'description': "Chef's version of charcuterie in a bowl.",
        'allergens': ['gluten', 'dairy'],
        'kaiNotes': 'Charcuterie board — contains cured meats, cheeses, and crackers.',
        'sortOrder': 3,
    },
    {
        'name': 'The No-Name',
        'category': 'To Share',
        'price': 8.0,
        'description': 'Baked Brie cheese, garlic, toasted bread, grilled tomatoes and grapes, served with pesto.',
        'allergens': ['gluten', 'dairy', 'nuts'],
        'isVegetarian': True,
        'kaiNotes': 'Pesto contains pine nuts. Brie is the main event.',
        'sortOrder': 4,
    },
    {
        'name': 'Goldilocks',
        'category': 'To Share',
        'price': 4.5,
        'description': 'A golden puff pastry braid stuffed with melty cheddar, smoky turkey, and fiery jalapeños, served with our house-made ranch sauce.',
        'allergens': ['gluten', 'dairy', 'eggs'],
        'isNew': True,
        'kaiNotes': 'Ranch sauce contains eggs and dairy. Pastry has gluten.',
        'sortOrder': 5,
    },
    {
        'name': 'Cornbread & Chestnuts',
        'category': 'To Share',
        'price': 6.0,
        'description': 'Cornbread & chestnuts with grilled grapes.',
        'allergens': ['gluten', 'nuts', 'eggs'],
        'isVegetarian': True,
        'kaiNotes': 'Chestnuts are tree nuts. Cornbread contains eggs.',
        'sortOrder': 6,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # SANDWICHES
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Grilled Cheese',
        'category': 'Sandwiches',
        'price': 6.0,
        'description': 'Gooey four cheese sandwich with garlic & caramelized onions with a bowl of tomato soup.',
        'allergens': ['gluten', 'dairy'],
        'isVegetarian': True,
        'isBestSeller': True,
        'sortOrder': 10,
    },
    {
        'name': 'The BFG',
        'category': 'Sandwiches',
        'price': 9.5,
        'description': 'Steak bits, cheese and caramelized onion with hand cut potatoes or french fries.',
        'allergens': ['gluten', 'dairy'],
        'isBestSeller': True,
        'sortOrder': 11,
    },
    {
        'name': 'Funguy',
        'category': 'Sandwiches',
        'price': 9.5,
        'description': 'Big grilled beef burger, mushroom mix with bacon, cheese with french fries. Vegan option available.',
        'allergens': ['gluten', 'dairy'],
        'canBeVegan': True,
        'kaiNotes': 'Vegan option available — ask to replace meat with plant patty.',
        'sortOrder': 12,
    },
    {
        'name': 'Griffin & Slaw',
        'category': 'Sandwiches',
        'price': 7.5,
        'description': 'A big sandwich of fried chicken, mountain of spicy coleslaw served with french fries.',
        'allergens': ['gluten', 'eggs'],
        'isNew': True,
        'kaiNotes': 'Coleslaw dressing contains eggs. Chicken is breaded (gluten).',
        'sortOrder': 13,
    },
    {
        'name': 'Onion Knight',
        'category': 'Sandwiches',
        'price': 9.5,
        'description': 'Big grilled beef burger, caramelized onions with bacon, cheese with french fries. Vegan option available.',
        'allergens': ['gluten', 'dairy'],
        'canBeVegan': True,
        'kaiNotes': 'Vegan option available — ask kitchen.',
        'sortOrder': 14,
    },
    {
        'name': 'Mean Madame',
        'category': 'Sandwiches',
        'price': 7.0,
        'description': 'A big sandwich of sunny-side up eggs with turkey, cheese and mornay sauce.',
        'allergens': ['gluten', 'dairy', 'eggs'],
        'kaiNotes': 'Mornay sauce is a butter and cheese sauce (dairy). Contains eggs.',
        'sortOrder': 15,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # HEARTY MEALS
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Clucking Waffles',
        'category': 'Hearty Meals',
        'price': 8.0,
        'description': 'Fried chicken on waffles, drizzled with maple syrup.',
        'allergens': ['gluten', 'dairy', 'eggs'],
        'isBestSeller': True,
        'kaiNotes': 'Waffles contain gluten, dairy, and eggs.',
        'sortOrder': 20,
    },
    {
        'name': 'Bangers & Smash',
        'category': 'Hearty Meals',
        'price': 8.0,
        'description': 'Mediterranean sausages with mashed potatoes and gravy.',
        'allergens': ['gluten', 'dairy'],
        'kaiNotes': 'Mash contains butter (dairy). Sausages may contain gluten.',
        'sortOrder': 21,
    },
    {
        'name': 'Clucking Roast',
        'category': 'Hearty Meals',
        'price': 14.0,
        'description': 'Whole roasted chicken with vegetables and lemon herb rub.',
        'allergens': ['dairy'],
        'isGlutenFree': True,
        'kaiNotes': 'Lower allergen risk. Check if herb rub contains dairy butter.',
        'sortOrder': 22,
    },
    {
        'name': 'Fish & Chips',
        'category': 'Hearty Meals',
        'price': 10.0,
        'description': 'Classic battered fish with chips.',
        'allergens': ['gluten', 'fish'],
        'kaiNotes': 'Contains fish and gluten (batter). Not suitable for fish allergy.',
        'sortOrder': 23,
    },
    {
        'name': "Bilbo's Second Breakfast",
        'category': 'Hearty Meals',
        'price': 10.0,
        'description': 'CAB tenderloin meat, 3 eggs your way and potato with mushrooms and eggplant.',
        'allergens': ['eggs'],
        'isGlutenFree': True,
        'isBestSeller': True,
        'kaiNotes': 'Gluten-free — great for guests who avoid gluten. Contains eggs.',
        'sortOrder': 24,
    },
    {
        'name': 'The Steak',
        'category': 'Hearty Meals',
        'price': 17.0,
        'description': '300g Sirloin steak served with mashed potatoes or french fries and roasted squash or roasted veggies.',
        'allergens': ['dairy'],
        'isNew': True,
        'kaiNotes': 'Dairy in mashed potatoes. Order with fries for lower allergen option.',
        'sortOrder': 25,
    },
    {
        'name': 'Arabasta Chicken Curry',
        'category': 'Hearty Meals',
        'price': 9.0,
        'description': "A treasured family recipe from our co-owner's grandma: tender chicken simmered in a rich red curry sauce with garden vegetables, served with fluffy rice.",
        'allergens': [],
        'isGlutenFree': True,
        'isNew': True,
        'isBestSeller': True,
        'kaiNotes': "Co-owner's family recipe. Rich red curry sauce — check dairy if sensitive.",
        'sortOrder': 26,
    },
    {
        'name': 'The Inquisition',
        'category': 'Hearty Meals',
        'price': 6.0,
        'description': 'Omelette mix of feta & herbed potatoes, eggplant with beef bacon.',
        'allergens': ['eggs', 'dairy'],
        'isGlutenFree': True,
        'kaiNotes': 'Gluten-free. Feta is dairy. Good option for gluten-free guests.',
        'sortOrder': 27,
    },
    {
        'name': 'Dragon Stew',
        'category': 'Hearty Meals',
        'price': 20.0,
        'description': 'Huge beef stew with potatoes, carrots, corn, peas, mushrooms and side of rustic bread.',
        'allergens': ['gluten'],
        'isBestSeller': True,
        'kaiNotes': 'Rustic bread is the source of gluten. Can be served without bread on request.',
        'sortOrder': 28,
    },
    {
        'name': 'Dungeon Delver',
        'category': 'Hearty Meals',
        'price': 19.0,
        'description': 'Cuts of beef tenderloin with mushroom sauce & hand cut potatoes with rustic bread.',
        'allergens': ['gluten', 'dairy'],
        'kaiNotes': 'Mushroom sauce likely contains cream (dairy). Rustic bread has gluten.',
        'sortOrder': 29,
    },
    {
        'name': 'The Barbarian',
        'category': 'Hearty Meals',
        'price': 20.0,
        'description': 'Lamb shank stew on bed of mushroom rice and vegetables.',
        'allergens': [],
        'isGlutenFree': True,
        'kaiNotes': 'Lower allergen risk. One of the more allergen-friendly mains.',
        'sortOrder': 30,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # FLATBREAD
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Cheesy Mushroom',
        'category': 'Flatbread',
        'price': 8.0,
        'description': 'Mushroom & cheese mix flatbread.',
        'allergens': ['gluten', 'dairy'],
        'isVegetarian': True,
        'sortOrder': 40,
    },
    {
        'name': 'Garden Scroll',
        'category': 'Flatbread',
        'price': 7.0,
        'description': 'Flatbread layered with roasted seasonal vegetables and herbs.',
        'allergens': ['gluten'],
        'isVegetarian': True,
        'isVegan': True,
        'sortOrder': 41,
    },
    {
        'name': 'Meat-a-Dor',
        'category': 'Flatbread',
        'price': 9.0,
        'description': 'Meat mix flatbread with cheese.',
        'allergens': ['gluten', 'dairy'],
        'sortOrder': 42,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # BOWLS & PIES
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Cottage Pie',
        'category': 'Bowls & Pies',
        'price': 8.0,
        'description': 'Potatoes, cheddar cheese & minced meats filling.',
        'allergens': ['dairy'],
        'kaiNotes': 'Cheddar topping is dairy. Check if potato base has gluten binder.',
        'sortOrder': 50,
    },
    {
        'name': 'Mrs Lovett Hand Pies',
        'category': 'Bowls & Pies',
        'price': 7.0,
        'description': 'Chicken & mushroom pie with garlic butter.',
        'allergens': ['gluten', 'dairy'],
        'isBestSeller': True,
        'sortOrder': 51,
    },
    {
        'name': "Bowl O' Chili",
        'category': 'Bowls & Pies',
        'price': 8.0,
        'description': 'Beef stew served with bread — slightly spicy. Vegan option available.',
        'allergens': ['gluten'],
        'canBeVegan': True,
        'kaiNotes': 'Vegan option available. Bread is the gluten source — can omit.',
        'sortOrder': 52,
    },
    {
        'name': 'Onion Soup',
        'category': 'Bowls & Pies',
        'price': 5.0,
        'description': 'Classic onion soup.',
        'allergens': ['gluten', 'dairy'],
        'isVegetarian': True,
        'kaiNotes': 'Likely served with croutons (gluten) and cheese topping (dairy).',
        'sortOrder': 53,
    },
    {
        'name': 'Red Lentil & Corn Soup',
        'category': 'Bowls & Pies',
        'price': 5.0,
        'description': 'Red lentil and corn soup.',
        'allergens': [],
        'isVegetarian': True,
        'isVegan': True,
        'isGlutenFree': True,
        'kaiNotes': 'Vegan and gluten-free. Good choice for dietary restrictions.',
        'sortOrder': 54,
    },
    {
        'name': 'Squash Soup',
        'category': 'Bowls & Pies',
        'price': 5.0,
        'description': 'Roasted squash soup.',
        'allergens': [],
        'isVegetarian': True,
        'isVegan': True,
        'isGlutenFree': True,
        'kaiNotes': 'Vegan and gluten-free. One of the safest options for allergies.',
        'sortOrder': 55,
    },
    {
        'name': "Coup O' Plenty",
        'category': 'Bowls & Pies',
        'price': 8.5,
        'description': 'A bowl of hot honey-glazed chicken on top garlic rice, with roasted carrots, steamed broccoli, & a dollop of home-made herb ranch sauce.',
        'allergens': ['dairy'],
        'isNew': True,
        'isBestSeller': True,
        'kaiNotes': 'Ranch sauce contains dairy. Otherwise relatively clean.',
        'sortOrder': 56,
    },
    {
        'name': 'Steak & Ale Pie',
        'category': 'Bowls & Pies',
        'price': 8.5,
        'description': 'Steak bites with a chili kick, garlic butter glazed carrots and peas.',
        'allergens': ['gluten', 'dairy'],
        'isBestSeller': True,
        'sortOrder': 57,
    },
    {
        'name': 'Spartan Bowl',
        'category': 'Bowls & Pies',
        'price': 10.0,
        'description': 'Grilled steak slices over a bed of garlic rice, with potatoes, sweet corn, steamed broccoli, and home-made cilantro sauce.',
        'allergens': [],
        'isGlutenFree': True,
        'isNew': True,
        'isBestSeller': True,
        'kaiNotes': 'One of the cleanest dishes — gluten-free and no major allergens.',
        'sortOrder': 58,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # BIG SALAD BOWL
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Greek Salad',
        'category': 'Big Salad Bowl',
        'price': 6.0,
        'description': 'Traditional Greek feta salad with lemon vinaigrette dressing.',
        'allergens': ['dairy'],
        'isVegetarian': True,
        'isGlutenFree': True,
        'kaiNotes': 'Gluten-free. Feta is dairy. Good for gluten-free guests.',
        'sortOrder': 60,
    },
    {
        'name': 'Caesar Salad',
        'category': 'Big Salad Bowl',
        'price': 5.0,
        'description': 'Original Caesar sauce. Additional grilled chicken +2 BHD.',
        'allergens': ['dairy', 'eggs', 'gluten', 'fish'],
        'kaiNotes': 'Caesar dressing contains anchovies (fish) and eggs. Croutons have gluten.',
        'sortOrder': 61,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # SWEET TOOTH
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Cookie Bones & Milk',
        'category': 'Sweet Tooth',
        'price': 4.0,
        'description': 'Freshly baked cookies served with milk.',
        'allergens': ['gluten', 'dairy', 'eggs'],
        'isVegetarian': True,
        'isNew': True,
        'isBestSeller': True,
        'sortOrder': 70,
    },
    {
        'name': "Chef's Cheesecake",
        'category': 'Sweet Tooth',
        'price': 4.0,
        'description': 'Cheesecake on a lotus/biscoff base.',
        'allergens': ['gluten', 'dairy', 'eggs'],
        'isVegetarian': True,
        'isNew': True,
        'isBestSeller': True,
        'kaiNotes': 'Lotus biscoff base contains gluten. Popular dessert.',
        'sortOrder': 71,
    },
    {
        'name': 'Clouds & Caramel',
        'category': 'Sweet Tooth',
        'price': 5.5,
        'description': 'Cream, caramel, dragonbeard and a crunchy surprise.',
        'allergens': ['dairy', 'gluten', 'nuts'],
        'isVegetarian': True,
        'kaiNotes': 'Crunchy surprise may contain nuts — check with kitchen for nut allergy.',
        'sortOrder': 72,
    },
    {
        'name': "Somethin' Sweet in a Cup",
        'category': 'Sweet Tooth',
        'price': 3.5,
        'description': 'Chocolate or carrot cake.',
        'allergens': ['gluten', 'dairy', 'eggs'],
        'isVegetarian': True,
        'sortOrder': 73,
    },
    {
        'name': 'Pumpkin Pie',
        'category': 'Sweet Tooth',
        'price': 6.0,
        'description': 'Classic pumpkin pie.',
        'allergens': ['gluten', 'dairy', 'eggs'],
        'isVegetarian': True,
        'sortOrder': 74,
    },
    {
        'name': 'Apple Pie',
        'category': 'Sweet Tooth',
        'price': 6.0,
        'description': 'Apple pie with vanilla ice cream.',
        'allergens': ['gluten', 'dairy', 'eggs'],
        'isVegetarian': True,
        'sortOrder': 75,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # KIDS MEALS
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Chicken Tenders',
        'category': 'Kids Meals',
        'price': 3.5,
        'description': 'Crispy chicken tenders served with french fries. For kids up to age 11.',
        'allergens': ['gluten'],
        'kaiNotes': "Kids meal. Chicken is breaded (gluten).",
        'sortOrder': 80,
    },
    {
        'name': 'Hot Doggie Dog',
        'category': 'Kids Meals',
        'price': 3.5,
        'description': 'Hot dog served with french fries. For kids up to age 11.',
        'allergens': ['gluten'],
        'sortOrder': 81,
    },
    {
        'name': 'Cheese Pizza',
        'category': 'Kids Meals',
        'price': 3.5,
        'description': 'Kids cheese pizza. Add chicken +2 BHD. For kids up to age 11.',
        'allergens': ['gluten', 'dairy'],
        'isVegetarian': True,
        'kaiNotes': 'Vegetarian base. Add chicken for +2 BHD.',
        'sortOrder': 82,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # EVERYDAY DRINKS — MOCKTAILS
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Iced Tea',
        'category': 'Everyday Drinks',
        'price': 3.0,
        'description': 'Lemon or peach iced tea.',
        'allergens': [],
        'isVegetarian': True, 'isVegan': True, 'isGlutenFree': True,
        'sortOrder': 90,
    },
    {
        'name': 'Lemonade',
        'category': 'Everyday Drinks',
        'price': 3.0,
        'description': 'Fresh lemonade — peach, lemon or passion fruit.',
        'allergens': [],
        'isVegetarian': True, 'isVegan': True, 'isGlutenFree': True,
        'sortOrder': 91,
    },
    {
        'name': 'Shirley Temple',
        'category': 'Everyday Drinks',
        'price': 2.5,
        'description': 'Classic non-alcoholic Shirley Temple.',
        'allergens': [],
        'isVegetarian': True, 'isVegan': True, 'isGlutenFree': True,
        'sortOrder': 92,
    },
    {
        'name': 'Virgin Mojito',
        'category': 'Everyday Drinks',
        'price': 4.0,
        'description': 'Non-alcoholic mojito.',
        'allergens': [],
        'isVegetarian': True, 'isVegan': True, 'isGlutenFree': True,
        'sortOrder': 93,
    },
    {
        'name': 'Secret Island',
        'category': 'Everyday Drinks',
        'price': 4.0,
        'description': 'AKA Piña Colada — non-alcoholic.',
        'allergens': [],
        'isVegetarian': True, 'isGlutenFree': True,
        'sortOrder': 94,
    },
    {
        'name': 'Punch — Apple Cinnamon',
        'category': 'Everyday Drinks',
        'price': 4.0,
        'description': 'Apple cinnamon punch.',
        'allergens': [],
        'isVegetarian': True, 'isVegan': True, 'isGlutenFree': True,
        'sortOrder': 95,
    },
    {
        'name': 'Punch — Strawberry Ginger',
        'category': 'Everyday Drinks',
        'price': 4.0,
        'description': 'Strawberry ginger punch.',
        'allergens': [],
        'isVegetarian': True, 'isVegan': True, 'isGlutenFree': True,
        'sortOrder': 96,
    },
    {
        'name': 'H2O',
        'category': 'Everyday Drinks',
        'price': 3.0,
        'description': 'Still or sparkling water. Large 3 BHD / Small 1.5 BHD.',
        'allergens': [],
        'isVegetarian': True, 'isVegan': True, 'isGlutenFree': True,
        'sortOrder': 97,
    },
    {
        'name': 'Soda',
        'category': 'Everyday Drinks',
        'price': 2.0,
        'description': 'Kinza, Diet Kinza, or Lemon Kinza.',
        'allergens': [],
        'isVegetarian': True, 'isVegan': True, 'isGlutenFree': True,
        'sortOrder': 98,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # EVERYDAY DRINKS — CLASSICS (non-alcoholic versions may be available)
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Sour on Sour',
        'category': 'Everyday Drinks',
        'price': 6.0,
        'description': 'AKA Whisky Sour. Non-alcoholic version may be available.',
        'allergens': [],
        'isGlutenFree': True,
        'kaiNotes': 'Classic cocktail/mocktail. Ask if guest wants non-alcoholic.',
        'sortOrder': 100,
    },
    {
        'name': 'Mojito',
        'category': 'Everyday Drinks',
        'price': 6.0,
        'description': 'Classic mojito. Non-alcoholic version available.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 101,
    },
    {
        'name': 'Moscow Mule',
        'category': 'Everyday Drinks',
        'price': 6.0,
        'description': 'Classic Moscow Mule.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 102,
    },
    {
        'name': 'Martini',
        'category': 'Everyday Drinks',
        'price': 6.0,
        'description': 'Espresso Martini or Classic Gin Martini.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 103,
    },
    {
        'name': 'Negroni',
        'category': 'Everyday Drinks',
        'price': 6.0,
        'description': 'Classic Negroni.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 104,
    },
    {
        'name': 'Manhattan',
        'category': 'Everyday Drinks',
        'price': 6.0,
        'description': 'Classic Manhattan cocktail.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 105,
    },
    {
        'name': 'Daiquiri',
        'category': 'Everyday Drinks',
        'price': 6.0,
        'description': 'Strawberry, Lemon, or Peach Daiquiri.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 106,
    },
    {
        'name': 'Long Island',
        'category': 'Everyday Drinks',
        'price': 8.0,
        'description': 'Long Island Iced Tea.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 107,
    },
    {
        'name': 'Gin & Basil',
        'category': 'Everyday Drinks',
        'price': 6.0,
        'description': 'Gin & Basil cocktail.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 108,
    },
    {
        'name': 'Bloody Mary',
        'category': 'Everyday Drinks',
        'price': 6.0,
        'description': 'Classic Bloody Mary.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 109,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # SIGNATURE CREATIONS (non-alcoholic versions may be available)
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'The Red Wedding',
        'category': 'Signature Creations',
        'price': 12.0,
        'description': 'A daring romantic drink for two. Includes an intimacy game for couples. Vodka & fruit based.',
        'allergens': [],
        'isGlutenFree': True,
        'kaiNotes': 'For two people. Includes a couple game. Romantic occasion drink.',
        'sortOrder': 110,
    },
    {
        'name': 'Cosmo Canyon',
        'category': 'Signature Creations',
        'price': 8.0,
        'description': 'Something hard and bitter. Citrus vodka based.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 111,
    },
    {
        'name': 'Wicked',
        'category': 'Signature Creations',
        'price': 6.0,
        'description': 'Like the witch… A fusion of gin.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 112,
    },
    {
        'name': 'Mad Margo',
        'category': 'Signature Creations',
        'price': 7.0,
        'description': 'Spicy mango margarita.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 113,
    },
    {
        'name': 'Sands of Time',
        'category': 'Signature Creations',
        'price': 6.0,
        'description': 'A whimsical drink inspired by the Arabian Deserts. Vodka, rum, coffee & cinnamon based.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 114,
    },
    {
        'name': 'Frostmourne',
        'category': 'Signature Creations',
        'price': 8.0,
        'description': 'A homage to the Lich King. Rum, gin, tequila & vodka based.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 115,
    },
    {
        'name': 'The Hades',
        'category': 'Signature Creations',
        'price': 7.0,
        'description': 'Made for a Greek God: peach schnapps, blue curaçao and overproof rum.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 116,
    },
    {
        'name': 'Peaches x5',
        'category': 'Signature Creations',
        'price': 6.0,
        'description': 'Gin based, peach liqueur & raspberry syrup.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 117,
    },
    {
        'name': 'Lights Out',
        'category': 'Signature Creations',
        'price': 7.0,
        'description': 'Vodka based, basil & ginger with cocoa liqueur and a pinch of salt.',
        'allergens': [],
        'isGlutenFree': True,
        'sortOrder': 118,
    },
    {
        'name': 'Spiked Butterbeer',
        'category': 'Signature Creations',
        'price': 7.0,
        'description': 'Sweet, creamy with a little kick — not for muggles to enjoy.',
        'allergens': ['dairy'],
        'kaiNotes': 'Creamy drink — contains dairy. Harry Potter reference.',
        'sortOrder': 119,
    },

    # ══════════════════════════════════════════════════════════════════════════
    # THEMATIC CREATIONS
    # ══════════════════════════════════════════════════════════════════════════
    {
        'name': 'Master of the House (Wine)',
        'category': 'Thematic Creations',
        'price': 4.0,
        'description': 'Red, White, or Rosé wine. Ask about our wine list.',
        'allergens': ['sulfites'],
        'isVegetarian': True, 'isGlutenFree': True,
        'kaiNotes': 'Wine contains sulfites. Ask about the full wine list.',
        'sortOrder': 120,
    },
    {
        'name': 'Skol',
        'category': 'Thematic Creations',
        'price': 4.5,
        'description': 'Served in a Viking Pint. Ale or draft beer. Non-alcoholic beer available 3 BHD.',
        'allergens': ['gluten'],
        'kaiNotes': 'Beer contains gluten. Non-alcoholic option available for 3 BHD.',
        'sortOrder': 121,
    },
    {
        'name': 'The Coven',
        'category': 'Thematic Creations',
        'price': 20.0,
        'description': 'Suitable for 3 guests. Liquified essence of lost souls. 20 BHD alcoholic / 13 BHD virgin.',
        'allergens': [],
        'isGlutenFree': True,
        'kaiNotes': 'Group drink for 3. Virgin version available for 13 BHD.',
        'sortOrder': 122,
    },
    {
        'name': "The Tribe's Shots",
        'category': 'Thematic Creations',
        'price': 4.0,
        'description': '4 BHD per shot. B52, Kamikaze, Brazilian, On the Beach, Brain Damage, Voo Doo People.',
        'allergens': [],
        'isGlutenFree': True,
        'kaiNotes': 'Individual shots. Multiple flavours available.',
        'sortOrder': 123,
    },
    {
        'name': "The Tavern's Potions",
        'category': 'Thematic Creations',
        'price': 20.0,
        'description': '3 potion globes served on a magical misty platter. Elixir of Health, Mana, and Stamina. 20 BHD alcoholic / 13 BHD kids-friendly.',
        'allergens': [],
        'isGlutenFree': True,
        'kaiNotes': 'Theatrical presentation. Kids-friendly version 13 BHD. Great for groups.',
        'sortOrder': 124,
    },
    {
        'name': 'The Three Devils',
        'category': 'Thematic Creations',
        'price': 15.0,
        'description': 'A fiery legend of three devilish shots, each hotter than the last, served with spicy chicken bites. Write your regret on flame-paper, toss it into the fire, and let it burn.',
        'allergens': ['gluten'],
        'kaiNotes': 'Theatrical experience — write a regret and burn it. Very spicy. Chicken bites contain gluten.',
        'sortOrder': 125,
    },
]

# ── Seed ──────────────────────────────────────────────────────────────────────

def seed():
    menu_ref = db.reference('menu')
    existing = menu_ref.get() or {}
    added = updated = skipped = 0

    for item in MENU:
        item  = dict(item)
        name  = item.get('name', '')
        if not name:
            continue

        # Fill defaults
        item.setdefault('isVegetarian', False)
        item.setdefault('isVegan',      False)
        item.setdefault('canBeVegan',   False)
        item.setdefault('isGlutenFree', False)
        item.setdefault('isNew',        False)
        item.setdefault('isBestSeller', False)
        item.setdefault('isAvailable',  True)
        item.setdefault('imageUrl',     '')
        item.setdefault('kaiNotes',     '')
        item['updatedAt'] = int(time.time() * 1000)

        key = _key(name)
        if FORCE and key in existing:
            db.reference(f'menu/{key}').update(item)
            print(f'  ↻  {name}')
            updated += 1
        elif key not in existing:
            item['createdAt'] = int(time.time() * 1000)
            db.reference(f'menu/{key}').set(item)
            print(f'  ＋  {name}')
            added += 1
        else:
            print(f'  ·  {name} (exists, skipping)')
            skipped += 1

    print(f'\n✅  Done — {added} added, {updated} updated, {skipped} skipped')
    print(f'   Total items in script: {len(MENU)}')
    if not FORCE:
        print('   Tip: run with --force to overwrite existing items')


if __name__ == '__main__':
    print(f'🍺  Seeding Tavern menu → kingdom-ac44f RTDB /menu')
    print(f'   Mode: {"FORCE UPDATE" if FORCE else "add-new-only"}\n')
    seed()
