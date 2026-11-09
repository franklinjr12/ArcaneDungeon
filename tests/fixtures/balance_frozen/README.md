# Frozen balance fixture (AD-167)

Frozen copies of the live balance files (magic_balance_v1, combat_tuning_v1, run_v2, difficulty_v1) taken for AD-167.
Golden/scenario tests load them through `TestContext.with_frozen_balance()`.
Live tuning must NOT edit these files; regenerate them only together with the golden traces.
