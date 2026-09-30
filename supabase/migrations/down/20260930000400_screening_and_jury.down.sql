drop table if exists results, rankings, scores, scoring_rubrics, conflicts, jury_assignments cascade;
drop function if exists current_juror_id();
drop table if exists jurors, honours cascade;
drop function if exists screening_decisions_supersede() cascade;
drop table if exists screening_decisions, screening_assignments, screening_flags cascade;
