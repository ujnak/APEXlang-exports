create or replace PROCEDURE tcq_callback(ntfnds IN SYS.CHNF$_DESC)
is
    l_reg_id          number;
    l_table_name      varchar2(261);
    l_event_type      number;
    l_table_operation number;
    l_row_operation   number;
    l_numrows         number;
    l_row_id          varchar2(2000);
    l_numqueries      number;
    l_qid             number;
    l_qop             number;
    /* notification message */
    l_sal     emp.sal%type;
    l_comm    emp.comm%type;
    l_is_sal  number;
    l_is_comm number;
    l_owner   tcq_notification_defs.owner%type;
    l_message tcq_notifications.message%type;
begin
    l_reg_id     := ntfnds.registration_id;
    l_event_type := ntfnds.event_type;
    -- Example 21-6 Creating Server-Side PL/SQL Notification Handler
    INSERT INTO nfevents (regid, event_type) VALUES (l_reg_id, l_event_type);

    if (l_event_type = DBMS_CQ_NOTIFICATION.EVENT_QUERYCHANGE) then
        l_numqueries := ntfnds.query_desc_array.count;
        for i in 1..l_numqueries
        loop
            l_qid := ntfnds.QUERY_DESC_ARRAY(i).queryid;
            l_qop := ntfnds.QUERY_DESC_ARRAY(i).queryop;

            -- Example 21-6 Creating Server-Side PL/SQL Notification Handler
            INSERT INTO nfqueries (qid, qop) VALUES(l_qid, l_qop);

            if l_qop = DBMS_CQ_NOTIFICATION.EVENT_DEREG then
                -- Queryが登録解除されたことを記録
                continue;
            elsif l_qop <> DBMS_CQ_NOTIFICATION.EVENT_QUERYCHANGE then
                continue;
            end if;

            /*
             * 変更通知の元である問い合わせを確認する。
             */
            l_is_sal  := 0;
            l_is_comm := 0;
            begin
                select
                    owner,
                    case when query_id_sal  = l_qid then 1 else 0 end,
                    case when query_id_comm = l_qid then 1 else 0 end
                into l_owner, l_is_sal, l_is_comm
                from tcq_notification_defs
                where reg_id = l_reg_id;
            exception
                when no_data_found then
                    l_is_sal := 0;
                    l_is_comm := 0;
            end;                 

            for j in 1..ntfnds.QUERY_DESC_ARRAY(i).table_desc_array.count
            loop
                /*
                 * 今回、想定している問い合わせでは、変更される表はEMPのみ。
                 */
                l_table_name := ntfnds.QUERY_DESC_ARRAY(i).table_desc_array(j).table_name;
                l_table_operation := ntfnds.QUERY_DESC_ARRAY(i).table_desc_array(j).opflags;

                -- Example 21-6 Creating Server-Side PL/SQL Notification Handler
                INSERT INTO nftablechanges (qid, table_name, table_operation) VALUES (l_qid, l_table_name, l_table_operation);

                if (bitand(l_table_operation, DBMS_CQ_NOTIFICATION.ALL_ROWS) = 0) then
                    l_numrows := ntfnds.query_desc_array(i).table_desc_array(j).numrows;
                else
                    /* ALL_ROWSは表全体の変更の可能性がある。 */
                    insert into tcq_notifications(receiver, message)
                    select owner, l_table_name || ' data changed but rowid is not available.'
                    from tcq_notification_defs
                    where reg_id = l_reg_id;
                    continue;
                end if;

                /* 
                 * 変更された行ごとに通知する。
                 */
                for k in 1..l_numrows
                loop
                    l_row_id := ntfnds.query_desc_array(i).table_desc_array(j).row_desc_array(k).row_id;
                    l_row_operation := ntfnds.query_desc_array(i).table_desc_array(j).row_desc_array(k).opflags;

                    -- Example 21-6 Creating Server-Side PL/SQL Notification Handler
                    INSERT INTO nfrowchanges (qid, table_name, row_id) VALUES (l_qid, l_table_name, l_row_id);

                    /* SALに関する通知 */
                    if l_is_sal = 1 then
                        if bitand(l_row_operation, DBMS_CQ_NOTIFICATION.DELETEOP) <> 0 then
                            l_message :=
                                'SAL query result changed because the EMP row was deleted.';
                            insert into tcq_notifications(receiver, message) values(l_owner, l_message);
                        elsif bitand(l_row_operation, DBMS_CQ_NOTIFICATION.INSERTOP) <> 0 
                           or bitand(l_row_operation, DBMS_CQ_NOTIFICATION.UPDATEOP) <> 0 then
                            begin
                                /* 変更された値ではなく、通知を受けたときの値。 */
                                select sal into l_sal from emp where rowid = CHARTOROWID(l_row_id) and ename = l_owner;
                                l_message :=
                                    'SAL query result changed. Current value is '
                                        || COALESCE(TO_CHAR(l_sal), 'NULL')
                                        || '.';
                              exception
                                when no_data_found then
                                    l_message := 'SAL query result changed and the row no longer matches the query.';
                            end;
                            insert into tcq_notifications(receiver, message) values(l_owner, l_message);
                        end if;
                    end if;
                    /* COMMに関する通知 */
                    if l_is_comm = 1 then
                        if bitand(l_row_operation, DBMS_CQ_NOTIFICATION.DELETEOP) <> 0 then
                            l_message :=
                                'COMM query result changed because the EMP row was deleted.';
                            insert into tcq_notifications(receiver, message) values(l_owner, l_message);
                        elsif bitand(l_row_operation, DBMS_CQ_NOTIFICATION.INSERTOP) <> 0 
                           or bitand(l_row_operation, DBMS_CQ_NOTIFICATION.UPDATEOP) <> 0 then
                            begin
                                /* 変更された値ではなく、通知を受けたときの値。 */
                                select comm into l_comm from emp where rowid = CHARTOROWID(l_row_id) and ename = l_owner;
                                l_message :=
                                    'COMM query result changed. Current value is '
                                        || COALESCE(TO_CHAR(l_comm), 'NULL')
                                        || '.';
                            exception
                                when no_data_found then
                                    l_message := 'COMM query result changed and the row no longer matches the query.';
                            end;
                            insert into tcq_notifications(receiver, message) values(l_owner, l_message);
                        end if;
                    end if;
                end loop;  /* loop over rows    */
            end loop;      /* loop over tables  */
        end loop;          /* loop over queries */
    end if;
    commit;
exception
    when others then
        rollback;
        -- 必要なら、別トランザクションのロガーで
        -- registration_id、transaction_id、SQLCODE、SQLERRMを記録
        raise;
end;
