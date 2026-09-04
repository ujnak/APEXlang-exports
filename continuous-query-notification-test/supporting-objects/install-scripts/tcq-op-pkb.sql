create or replace package body tcq_op as
procedure register(p_username in varchar2, p_reg_id in number default null)
/**
 * Query Result Change Notification - 問い合わせ結果変更通知を登録する。
 * 
 * 登録対象は表EMP、p_usernameとして与えられた従業員の給与(列SAL）または手当(列COMM)の値が
 * 変更されたときに、変更された対象の従業員へ通知することを想定している。
 * 通知はコールバック・プロシージャTCQ_CALLBACKが実施する。
 *
 * Ref:
 * Database Development Guide, Relase 26
 * 21.2 About Query Result Change Notification (QRCN)
 * https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/cqn.html#GUID-2E64E453-ADBE-4DFA-94C0-39A0AA4081E9
 */
as
    l_reginfo       CQ_NOTIFICATION$_REG_INFO;
    l_cursor        SYS_REFCURSOR;
    l_reg_id        tcq_notification_defs.reg_id%type;
    l_query_id_sal  tcq_notification_defs.query_id_sal%type;
    l_query_id_comm tcq_notification_defs.query_id_comm%type;
    l_qosflags      number;
    l_reg_block_open boolean := FALSE;
begin
    /*
     * 問い合わせ結果変更通知の登録。
     * https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/DBMS_CQ_NOTIFICATION.html#ARPLS-GUID-C92C877D-5795-4DB4-8C50-E694A15E27FA
     */
    if p_reg_id is null then
        /* 
         * 通知方式。
         * CQ_NOTIFICATION$_REG_INFO
         * https://docs.oracle.com/en/database/oracle/oracle-database/26/adfns/cqn.html#GUID-05EB875B-7ED8-4C06-B862-D339FEC3571B
         */
        l_qosflags := DBMS_CQ_NOTIFICATION.QOS_QUERY
                    + DBMS_CQ_NOTIFICATION.QOS_ROWIDS
                    -- + DBMS_CQ_NOTIFICATION.QOS_RELIABLE
                    -- 重要な通知ではQOS_RELIABLEフラグを立てる
                    ;
        l_reginfo := CQ_NOTIFICATION$_REG_INFO('tcq_callback', l_qosflags,0, 0, 0);
        l_reg_id := DBMS_CQ_NOTIFICATION.NEW_REG_START(l_reginfo);
    else
        DBMS_CQ_NOTIFICATION.ENABLE_REG(p_reg_id);
        l_reg_id := p_reg_id;
    end if;
    l_reg_block_open := TRUE;

    /*
     * QUERYIDの登録。
     * https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/DBMS_CQ_NOTIFICATION.html#GUID-C620AA0E-DC5F-43E5-8338-EE7FF0604166
     */

    /* 
     * 給与(SAL)の変更。
     */
    open l_cursor for 
        SELECT DBMS_CQ_NOTIFICATION.CQ_NOTIFICATION_QUERYID, sal
        FROM emp
        WHERE ename = p_username;
        l_query_id_sal := DBMS_CQ_NOTIFICATION.CQ_NOTIFICATION_QUERYID;
    close l_cursor;

    /*
     * 手当(COMM)の変更。
     */
    open l_cursor for
        SELECT DBMS_CQ_NOTIFICATION.CQ_NOTIFICATION_QUERYID, comm
        FROM emp
        WHERE ename = p_username;
        l_query_id_comm := DBMS_CQ_NOTIFICATION.CQ_NOTIFICATION_QUERYID;
    close l_cursor;

    /*
     * 登録の終了。
     * https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/DBMS_CQ_NOTIFICATION.html#GUID-16A5ABD4-2949-498D-ABE3-98AFF9AF3A5F
     */
    DBMS_CQ_NOTIFICATION.REG_END;
    l_reg_block_open := FALSE;

    insert into tcq_notification_defs(owner, reg_id, query_id_sal, query_id_comm) values(p_username, l_reg_id, l_query_id_sal, l_query_id_comm);
    commit;
exception
    when others then
        if l_cursor%isopen then
            close l_cursor;
        end if;

        if l_reg_block_open then
            begin
                DBMS_CQ_NOTIFICATION.REG_END;
            exception
                when others then
                    null; -- 本来は別途ログへ記録
            end;
        end if;

        if l_reg_id IS NOT NULL then
            begin
                DBMS_CQ_NOTIFICATION.DEREGISTER(l_reg_id);
            exception
                when others then
                    null; -- 元の例外を失わないため
            end;
        end if;

    rollback;
    raise;
end register;

procedure deregister(p_reg_id in number)
/*
 * 問い合わせ結果変更通知を削除する。
 */
as
begin
    DBMS_CQ_NOTIFICATION.DEREGISTER(p_reg_id);
    delete from tcq_notification_defs where reg_id = p_reg_id;
    commit;
exception
    when no_data_found then
        return;
end deregister;

end tcq_op;