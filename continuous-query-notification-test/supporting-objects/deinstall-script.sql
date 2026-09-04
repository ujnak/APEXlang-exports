drop procedure if exists tcq_callback;
drop package if exists tcq_op;
drop table if exists nfevents purge;
drop table if exists nfqueries purge;
drop table if exists nftablechanges purge;
drop table if exists nfrowchanges purge;
drop table if exists tcq_notification_defs purge;
drop table if exists tcq_notifications purge;