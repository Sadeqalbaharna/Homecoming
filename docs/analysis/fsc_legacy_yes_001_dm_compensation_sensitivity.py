"""Find My Table DM-compensation sensitivity model.

All margins, overheads, compensation amounts, setup allowances, and shadow
labor values are decision assumptions. Sponsor-attested operating facts are
limited to BHD12 minimum spend, four players per average table, two filled
tables per week, venue ownership, and the stated player/DM/matching bottlenecks.
"""

from math import ceil

BHD_PER_PLAYER = 12.0
BASE_SEATS = 4
CONTRIBUTION_MARGINS = (0.25, 0.40, 0.55, 0.70)
INCREMENTAL_OVERHEADS_BHD = (0.0, 5.0, 10.0)
CENTRAL_MARGIN = 0.40
CENTRAL_OVERHEAD_BHD = 5.0
SETUP_RECOVERY_ALLOWANCE_BHD = 20.0
DM_TOTAL_HOURS_RANGE = (2.5, 4.0)


def table_gross(seats: int) -> float:
    return seats * BHD_PER_PLAYER


def compensation_cost(
    structure: str,
    value: float,
    seats: int,
) -> float:
    gross = table_gross(seats)
    if structure in {"fixed_fee", "venue_credit"}:
        return value
    if structure == "gross_revenue_share":
        return gross * value
    if structure == "volunteer_shadow_value":
        return value
    raise ValueError(f"Unknown structure: {structure}")


def table_contribution(
    structure: str,
    value: float,
    seats: int,
    margin: float,
    overhead_bhd: float,
    new_player_fraction: float = 1.0,
) -> float:
    if not 0 <= new_player_fraction <= 1:
        raise ValueError("new_player_fraction must be between 0 and 1")
    pre_dm_contribution = (
        table_gross(seats) * new_player_fraction * margin - overhead_bhd
    )
    return round(
        pre_dm_contribution - compensation_cost(structure, value, seats),
        2,
    )


def break_even_seats(
    structure: str,
    value: float,
    margin: float,
    overhead_bhd: float,
    maximum_seats: int = 20,
):
    for seats in range(1, maximum_seats + 1):
        if table_contribution(
            structure,
            value,
            seats,
            margin,
            overhead_bhd,
        ) >= 0:
            return seats
    return None


def tables_to_recover_setup(net_per_table: float):
    if net_per_table <= 0:
        return None
    return ceil(SETUP_RECOVERY_ALLOWANCE_BHD / net_per_table)


scenario_options = {
    "fixed_fee": (6.0, 10.0, 15.0, 20.0),
    "gross_revenue_share": (0.10, 0.15, 0.20, 0.25),
    "venue_credit": (6.0, 12.0, 18.0, 24.0),
    "volunteer_shadow_value": (10.0, 15.0, 20.0, 25.0),
}

central_scenarios = []
for structure, values in scenario_options.items():
    for value in values:
        net = table_contribution(
            structure,
            value,
            BASE_SEATS,
            CENTRAL_MARGIN,
            CENTRAL_OVERHEAD_BHD,
        )
        central_scenarios.append(
            {
                "structure": structure,
                "value": value,
                "display_value": (
                    f"{value:.0%} of gross"
                    if structure == "gross_revenue_share"
                    else f"BHD{value:g}"
                ),
                "seats": BASE_SEATS,
                "gross_bhd": table_gross(BASE_SEATS),
                "margin": CENTRAL_MARGIN,
                "overhead_bhd": CENTRAL_OVERHEAD_BHD,
                "dm_cost_bhd": round(
                    compensation_cost(structure, value, BASE_SEATS), 2
                ),
                "implied_dm_hourly_bhd_range": (
                    round(
                        compensation_cost(structure, value, BASE_SEATS)
                        / DM_TOTAL_HOURS_RANGE[1],
                        2,
                    ),
                    round(
                        compensation_cost(structure, value, BASE_SEATS)
                        / DM_TOTAL_HOURS_RANGE[0],
                        2,
                    ),
                ),
                "net_contribution_bhd": net,
                "break_even_seats": break_even_seats(
                    structure,
                    value,
                    CENTRAL_MARGIN,
                    CENTRAL_OVERHEAD_BHD,
                ),
                "tables_to_recover_bhd20_setup": tables_to_recover_setup(net),
            }
        )


recommended_structure = "fixed_fee"
recommended_value = 10.0
recommended_margin_threshold = round(
    (recommended_value + CENTRAL_OVERHEAD_BHD)
    / table_gross(BASE_SEATS),
    4,
)
recommended_net_new_player_fraction_threshold = round(
    (recommended_value + CENTRAL_OVERHEAD_BHD)
    / (table_gross(BASE_SEATS) * CENTRAL_MARGIN),
    5,
)

recommended_sensitivity = []
for margin in CONTRIBUTION_MARGINS:
    for overhead in INCREMENTAL_OVERHEADS_BHD:
        recommended_sensitivity.append(
            {
                "margin": margin,
                "overhead_bhd": overhead,
                "four_seat_net_bhd": table_contribution(
                    recommended_structure,
                    recommended_value,
                    BASE_SEATS,
                    margin,
                    overhead,
                ),
                "break_even_seats": break_even_seats(
                    recommended_structure,
                    recommended_value,
                    margin,
                    overhead,
                ),
            }
        )


four_week_scale_floor = {
    "additional_tables": 4,
    "players_per_table": BASE_SEATS,
    "minimum_gross_bhd": 4 * table_gross(BASE_SEATS),
    "note": "Gross floor only; not contribution, profit, or forecast.",
}


model_summary = {
    "sponsor_attested": {
        "minimum_spend_per_player_bhd": BHD_PER_PLAYER,
        "average_players_per_table": BASE_SEATS,
        "current_filled_tables_per_week": 2,
        "current_minimum_weekly_gross_bhd": 2 * table_gross(BASE_SEATS),
    },
    "central_case_assumptions": {
        "venue_contribution_margin": CENTRAL_MARGIN,
        "incremental_overhead_per_table_bhd": CENTRAL_OVERHEAD_BHD,
        "setup_recovery_allowance_bhd": SETUP_RECOVERY_ALLOWANCE_BHD,
    },
    "recommended_default_pending_sponsor": {
        "structure": recommended_structure,
        "delivered_session_fee_bhd": recommended_value,
        "minimum_four_seat_margin_required": recommended_margin_threshold,
        "minimum_net_new_player_fraction_required": (
            recommended_net_new_player_fraction_threshold
        ),
        "implied_dm_hourly_bhd_range": (
            round(recommended_value / DM_TOTAL_HOURS_RANGE[1], 2),
            round(recommended_value / DM_TOTAL_HOURS_RANGE[0], 2),
        ),
        "central_case_net_per_table_bhd": table_contribution(
            recommended_structure,
            recommended_value,
            BASE_SEATS,
            CENTRAL_MARGIN,
            CENTRAL_OVERHEAD_BHD,
        ),
        "central_case_break_even_seats": break_even_seats(
            recommended_structure,
            recommended_value,
            CENTRAL_MARGIN,
            CENTRAL_OVERHEAD_BHD,
        ),
    },
    "four_week_scale_floor": four_week_scale_floor,
}


if __name__ == "__main__":
    from pprint import pprint

    pprint(model_summary)
    print("\nCentral compensation scenarios:")
    pprint(central_scenarios)
    print("\nRecommended fixed-fee sensitivity:")
    pprint(recommended_sensitivity)
