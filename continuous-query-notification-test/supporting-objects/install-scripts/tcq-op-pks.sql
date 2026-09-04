create or replace package tcq_op as
procedure register(p_username in varchar2, p_reg_id in number default null);
procedure deregister(p_reg_id in number);
end tcq_op;