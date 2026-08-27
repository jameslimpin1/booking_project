{{ config(
    materialized = 'incremental',
    unique_key = 'conversation_id',
    incremental_strategy = 'delete+insert',
    tags = ['staging']
) }}

-- generated_at doubles as the incremental cursor: on a re-run, only rows
-- generated after the newest one already loaded are pulled in, instead of
-- rescanning the full source every time.
select *
from {{ source('raw', 'dim_conversations') }}

{% if is_incremental() %}
where generated_at > (select max(generated_at) from {{ this }})
{% endif %}
