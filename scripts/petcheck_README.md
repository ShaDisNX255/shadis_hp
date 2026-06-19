# `petcheck` Dialogue Event README

The `petcheck` dialogue event checks the player's currently equipped pet and routes the dialogue based on whether the pet passes every configured condition.

This event does **not** remember rewards, mark quests complete, or manage repeat logic. Use your normal Tiled/ezlibs quest flow for that, such as an `itemcheck`, reward node, and quest completion item.

## Basic behavior

```text
Dialogue Type = petcheck
Next 1 = pass_dialogue
Next 2 = fail_dialogue
```

- `Next 1` runs if a pet is equipped and every configured check passes.
- `Next 2` runs if there is no equipped pet or any configured check fails.

Every extra property you add is treated as required. For example, if you set `Mood = happy`, `Pet Type = mettaur`, and `Min HP = 80`, the equipped pet must satisfy all three checks.

## Recommended quest flow

Use your existing `itemcheck` first to avoid repeating the quest reward.

```text
Dialogue Type = itemcheck
Item 1 = pet_quest_done_item
Next 1 = already_completed_dialogue
Next 2 = pet_check_dialogue
```

Then the `petcheck` dialogue handles the pet requirement.

```text
Dialogue Type = petcheck
Mood = happy
Next 1 = give_reward_dialogue
Next 2 = pet_not_ready_dialogue
```

Then your reward dialogue can give money, items, or any other reward through your usual ezlibs/Tiled setup, including the quest completion item.

---

# Required property

## `Dialogue Type`

Tells eznpcs to run this checker event.

```text
Dialogue Type = petcheck
```

---

# Branching properties

## `Next 1`

Dialogue to go to if the equipped pet passes every configured check.

```text
Next 1 = pet_passed
```

## `Next 2`

Dialogue to go to if there is no equipped pet, or if any configured check fails.

```text
Next 2 = pet_failed
```

---

# Mood checker

## `Mood`

Checks the pet's mood.

Common values:

```text
happy
neutral
sad
```

Example:

```text
Dialogue Type = petcheck
Mood = happy
Next 1 = pet_is_happy
Next 2 = pet_not_happy
```

---

# Pet type checker

## `Pet Type`

Checks the internal pet kind.

Example:

```text
Dialogue Type = petcheck
Pet Type = mettaur
Next 1 = has_mettaur
Next 2 = not_mettaur
```

## `Kind`

Alias for `Pet Type`.

Example:

```text
Dialogue Type = petcheck
Kind = mettaur
Next 1 = has_mettaur
Next 2 = not_mettaur
```

The checker also accepts values with the `pet_` prefix.

```text
Dialogue Type = petcheck
Pet Type = pet_mettaur
Next 1 = has_mettaur
Next 2 = not_mettaur
```

Example internal pet kinds:

```text
mettaur
ratty
swordy
powie
meddy
spooky
moloko
kabutank
jelly
volgear
magtect
fishy
piranha
brushman
bunny
```

---

# HP stat checker

## `Min HP`

Pet HP must be at least this much.

```text
Dialogue Type = petcheck
Min HP = 80
Next 1 = strong_pet_hp
Next 2 = weak_pet_hp
```

## `Max HP`

Pet HP must be no higher than this.

```text
Dialogue Type = petcheck
Max HP = 80
Next 1 = hp_is_80_or_less
Next 2 = hp_too_high
```

## HP range example

```text
Dialogue Type = petcheck
Min HP = 40
Max HP = 80
Next 1 = hp_in_range
Next 2 = hp_out_of_range
```

---

# Attack checker

## `Min Attack`

Pet's final displayed attack value must be at least this much.

```text
Dialogue Type = petcheck
Min Attack = 25
Next 1 = pet_hits_hard
Next 2 = pet_needs_training
```

## `Max Attack`

Pet's final displayed attack value must be no higher than this.

```text
Dialogue Type = petcheck
Max Attack = 50
Next 1 = attack_is_50_or_less
Next 2 = attack_too_high
```

Attack is usually based on the pet's attack rank. For example, a rank 5 pet usually has `Attack = 25`.

---

# Attack rank checker

## `Min Attack Rank`

Pet's internal attack rank must be at least this much.

```text
Dialogue Type = petcheck
Min Attack Rank = 10
Next 1 = trained_pet
Next 2 = not_trained_enough
```

## `Max Attack Rank`

Pet's internal attack rank must be no higher than this.

```text
Dialogue Type = petcheck
Max Attack Rank = 20
Next 1 = rank_20_or_less
Next 2 = rank_too_high
```

## `Min Rank`

Alias for `Min Attack Rank`.

```text
Dialogue Type = petcheck
Min Rank = 10
Next 1 = trained_pet
Next 2 = not_trained_enough
```

## `Max Rank`

Alias for `Max Attack Rank`.

```text
Dialogue Type = petcheck
Max Rank = 20
Next 1 = rank_20_or_less
Next 2 = rank_too_high
```

---

# Battle-ready checker

## `Battle Ready`

Use this when you want to know if the pet can join the player in battle.

```text
Dialogue Type = petcheck
Battle Ready = true
Next 1 = pet_can_join_battle
Next 2 = pet_cannot_join_battle
```

This passes only if:

- a pet is equipped
- the pet has a battle form
- the pet is not currently summoned

This fails if:

- no pet is equipped
- the pet has no battle form
- the pet is currently summoned

---

# Can-fight checker

## `Can Fight`

Checks whether the equipped pet has a battle-compatible form.

Example requiring a battle pet:

```text
Dialogue Type = petcheck
Can Fight = true
Next 1 = battle_pet_equipped
Next 2 = not_a_battle_pet
```

Example requiring a non-battle pet:

```text
Dialogue Type = petcheck
Can Fight = false
Next 1 = non_battle_pet_equipped
Next 2 = battle_pet_equipped
```

---

# Summoned checker

## `Summoned`

Checks whether the equipped pet is currently summoned on the overworld.

Example requiring the pet to not be summoned:

```text
Dialogue Type = petcheck
Summoned = false
Next 1 = pet_is_available
Next 2 = pet_is_summoned
```

Example requiring the pet to be summoned:

```text
Dialogue Type = petcheck
Summoned = true
Next 1 = pet_is_following_you
Next 2 = pet_is_not_summoned
```

---

# Boolean values

For `Battle Ready`, `Can Fight`, and `Summoned`, these count as true:

```text
true
yes
1
on
```

These count as false:

```text
false
no
0
off
```

---

# Combined examples

## Happy equipped pet

```text
Dialogue Type = petcheck
Mood = happy
Next 1 = happy_pet_reward
Next 2 = pet_not_happy
```

## Happy Mettaur

```text
Dialogue Type = petcheck
Mood = happy
Pet Type = mettaur
Next 1 = happy_mettaur
Next 2 = not_happy_mettaur
```

## Battle-ready Mettaur with at least 80 HP

```text
Dialogue Type = petcheck
Battle Ready = true
Pet Type = mettaur
Min HP = 80
Next 1 = mettaur_can_battle
Next 2 = mettaur_not_ready
```

## Strong battle pet, not summoned

```text
Dialogue Type = petcheck
Can Fight = true
Summoned = false
Min Attack Rank = 10
Next 1 = strong_pet_ready
Next 2 = pet_not_ready
```

## Happy, battle-ready pet

```text
Dialogue Type = petcheck
Mood = happy
Battle Ready = true
Next 1 = happy_pet_can_battle
Next 2 = pet_not_ready
```

---

# Notes

- The checker only reads the currently equipped pet.
- It does not award items or money by itself.
- It does not mark quests complete by itself.
- It does not store reward history by itself.
- Use your normal Tiled dialogue chain for reward and completion logic.
