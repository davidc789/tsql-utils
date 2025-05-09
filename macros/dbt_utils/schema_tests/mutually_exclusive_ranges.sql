{% macro fabric__test_mutually_exclusive_ranges(model, lower_bound_column, upper_bound_column, partition_by=None, gaps='allowed', zero_length_range_allowed=False) %}

{% if gaps == 'not_allowed' %}
    {% set allow_gaps_operator='=' %}
    {% set allow_gaps_operator_in_words='equal_to' %}
{% elif gaps == 'allowed' %}
    {% set allow_gaps_operator='<=' %}
    {% set allow_gaps_operator_in_words='less_than_or_equal_to' %}
{% elif gaps == 'required' %}
    {% set allow_gaps_operator='<' %}
    {% set allow_gaps_operator_in_words='less_than' %}
{% else %}
    {{ exceptions.raise_compiler_error(
        "`gaps` argument for mutually_exclusive_ranges test must be one of ['not_allowed', 'allowed', 'required'] Got: '" ~ gaps ~"'.'"
    ) }}
{% endif %}
{% if not zero_length_range_allowed %}
    {% set allow_zero_length_operator='<' %}
    {% set allow_zero_length_operator_in_words='less_than' %}
{% elif zero_length_range_allowed %}
    {% set allow_zero_length_operator='<=' %}
    {% set allow_zero_length_operator_in_words='less_than_or_equal_to' %}
{% else %}
    {{ exceptions.raise_compiler_error(
        "`zero_length_range_allowed` argument for mutually_exclusive_ranges test must be one of [true, false] Got: '" ~ zero_length_range_allowed ~"'.'"
    ) }}
{% endif %}

{% set partition_clause="partition by " ~ partition_by if partition_by else '' %}

with window_functions as (

    select
        {% if partition_by %}
        {{ partition_by }},
        {% endif %}
        {{ lower_bound_column }} as lower_bound,
        {{ upper_bound_column }} as upper_bound,

        lead({{ lower_bound_column }}) over (
            {{ partition_clause }}
            order by {{ lower_bound_column }}
        ) as next_lower_bound,

        case when
            row_number() over (
                {{ partition_clause }}
                order by {{ lower_bound_column }} desc
            ) = 1
        then 1 else 0 end as is_last_record
    from {{ model }}

),

calc as (
    -- We want to return records where one of our assumptions fails, so we'll use
    -- the `not` function with `and` statements so we can write our assumptions nore cleanly
    select
        *,

        --TODO turn thesse into null ifs or case whens...

        -- For each record: lower_bound should be < upper_bound.
        -- Coalesce it to return an error on the null case (implicit assumption
        -- these columns are not_null)
        iif(lower_bound {{ allow_zero_length_operator }} upper_bound, 1, 0)
            as lower_bound_{{ allow_zero_length_operator_in_words }}_upper_bound,

        -- For each record: upper_bound {{ allow_gaps_operator }} the next lower_bound.
        -- Coalesce it to handle null cases for the last record.
        iif(upper_bound {{ allow_gaps_operator }} next_lower_bound or is_last_record = 1, 1, 0)
            as upper_bound_{{ allow_gaps_operator_in_words }}_next_lower_bound

    from window_functions

),

validation_errors as (

    select
        *
    from calc

    where not (
        -- THE FOLLOWING SHOULD BE TRUE --
        lower_bound_{{ allow_zero_length_operator_in_words }}_upper_bound = 1
        and upper_bound_{{ allow_gaps_operator_in_words }}_next_lower_bound = 1
    )
)

select *
from validation_errors
{% endmacro %}
