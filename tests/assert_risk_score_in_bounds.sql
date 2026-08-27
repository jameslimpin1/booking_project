-- Fails if any cancellation_risk_score falls outside [0, 1]
select *
from {{ ref('int_booking_cancellation_risk') }}
where cancellation_risk_score < 0 or cancellation_risk_score > 1
