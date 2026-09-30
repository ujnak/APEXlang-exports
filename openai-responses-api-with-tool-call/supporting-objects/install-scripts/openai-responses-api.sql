create or replace procedure openai_responses_api( 
    p_model         in varchar2 
    ,p_input        in varchar2 
    ,p_instructions in varchar2 
    ,p_response_id  in out varchar2
    ,p_tool_set     in varchar2 default null
    ,p_output_text  out clob
    ,p_annotations  out clob 
    ,p_usage        out clob
    ,p_refusal      out clob
    ,p_summary_text out clob
    ,p_status            out varchar2 -- [completed,failed,in_progress,incomplete] 
    ,p_incomplete_reason out varchar2
    ,p_error_code        out varchar2
    ,p_error_message     out varchar2
    /* デフォルトで使用する限り無視できる。 */
    ,p_endpoint             in varchar2 default 'https://api.openai.com/v1/responses' 
    ,p_credential_static_id in varchar2 default 'OPENAI_API_KEY'
    ,p_tool_call_max in number default 10
    ,p_collection_name in varchar2 default 'PTC_LOG'
) 
as 
    /* ログ出力の上限。 */
    C_LOG_MESSAGE_MAX constant integer := 1000;
    /* ツール呼び出しの上限。 */
    C_TOOL_CALL_MAX   integer := p_tool_call_max;
    /* Programmatic Tool Callingのログ。 */
    C_COLLECTION_NAME varchar2(80) := p_collection_name;

    /* リクエストの作成に使用する */
    l_request      clob;
    l_request_json json_object_t; 
    l_tools        json_array_t; 
    l_tool         json_object_t; 
    l_reasoning    json_object_t; 
    l_input        json_array_t; 
    l_input_obj    json_object_t;
    /* レスポンスの処理に使用する。 */ 
    l_response      clob; 
    l_response_json json_object_t; 
    l_object        varchar2(40); 
    l_output        json_array_t; 
    l_output_size   integer; 
    l_output_obj    json_object_t; 
    l_output_obj_type   varchar2(40); 
    l_output_obj_status varchar2(40); 
    l_output_obj_role   varchar2(40); 
    l_output_text      clob; 
    /* 
    * 
    */
    l_content          json_array_t; 
    l_content_size     integer; 
    l_content_obj      json_object_t; 
    l_content_obj_type varchar2(20); 
    l_annotations json_array_t; 
    l_annotations_single json_array_t; 
    /*
    * typeがrefusal
    */
    l_refusal     clob;
    /*
    * reasoning sumary
    */
    l_summary      json_array_t;
    l_summary_size integer;
    l_summary_text clob;
    l_summary_obj json_object_t; 
    l_summary_obj_type varchar2(20); 
    /* 
    * usage 
    */ 
    l_usage json_object_t; 
    /*
    * 失敗時のレスポンス
    */
    l_incomplete_details json_object_t;
    l_error              json_object_t;
    /* 
    * Programatic Tool Calling
    */
    l_parameters    json_object_t;
    l_output_schema json_object_t;
    l_tool_call_count integer := 0;
    l_tool_call_id  varchar2(80);
    l_tool_caller   json_object_t;
    l_tool_caller_string varchar2(4000);
    l_is_programmatic boolean := false;
    l_function_call json_object_t;
    l_tool_input    json_object_t;
    l_tool_inputs   json_array_t;
    l_function_name varchar2(160);
    l_function_args clob;
    l_function_arg_obj json_object_t;
    l_dynamic_sql   varchar2(4000);
    l_function_out  clob;
    l_has_final_message boolean := false;
    l_function_exist number;
    l_program_code  clob;
begin 
    l_request_json := json_object_t(); 
    /* modelはページ・アイテムに選択可能な静的リストとして定義している。 */
    l_request_json.put('model', p_model); 
    /* reponse idが与えられていれば、前回の会話を継続させる。 */
    if p_response_id is not null then
        l_request_json.put('previous_response_id', p_response_id);
    end if;
    /*
    * 極端にトークンが消費されないように上限を設定する。
    */
    l_request_json.put('max_tool_calls', 5);
    l_request_json.put('max_output_tokens', 32768);
    /*
    * ツール定義を含める。今回はProgrammatic Tool Callingを前提とする。
    */ 
    if p_model in ('gpt-6-astra','gpt-6-sol','gpt-6-luna') then
        if p_tool_set is not null then
            /*
            * tool_setの定義がある場合は、カスタムのツール定義を含める。
            */
            l_tools := json_array_t();
            l_is_programmatic := false;
            for r in (
                select * from openai_tools where tool_set = p_tool_set
            )
            loop
                if r.tool_type = 'function' then
                    l_tool := json_object_t();
                    l_tool.put('type','function');
                    l_tool.put('name', r.tool_name);
                    l_tool.put('description', r.description);
                    /* parametersにはJSON Schemaがそのまま設定されている */
                    l_parameters := json_object_t(r.parameters);
                    l_tool.put('parameters', l_parameters);
                    /* output_schemaにはJSON Schemaがそのまま設定されている。 */
                    l_output_schema := json_object_t(r.output_schema);
                    l_tool.put('output_schema', l_output_schema);
                    /* allowed_callersがprogrammaticを含むか確認する。 */
                    if r.allowed_callers is null or r.allowed_callers like '%programmatic%' then
                        l_is_programmatic := true;
                    end if;
                    l_tool.put('allowed_callers', json_array_t(coalesce(r.allowed_callers,'["programmatic"]')));
                elsif r.tool_type = 'mcp' then
                    l_tool := json_object_t();
                    l_tool.put('type','mcp');
                    l_tool.put('server_label', r.server_label);
                    l_tool.put('server_url', r.server_url);
                    l_tool.put('allowed_tools', json_array_t(r.allowed_tools));
                    /* allowed_callersがprogrammaticを含むか確認する。 */
                    if r.allowed_callers is null or r.allowed_callers like '%programmatic%' then
                        l_is_programmatic := true;
                    end if;
                    l_tool.put('allowed_callers', json_array_t(coalesce(r.allowed_callers,'["programmatic"]')));
                    /* request_approvalを受け付けるコードを書いていないので、これはneverを設定する。 */
                    l_tool.put('require_approval', 'never');
                    l_tools.append(l_tool);
                end if;
            end loop;
            /*
            * 呼び出し可能なツールのallowed_callersにprogrammaticを含むものがあれば、
            * typeをprogrammatic_tool_callingとする。
            */
            if l_tools.get_size() > 0 and l_is_programmatic then
                l_tool := json_object_t();
                l_tool.put('type','programmatic_tool_calling');
                l_tools.append(l_tool);
            end if;
            l_request_json.put('tools', l_tools);
        else
            /* デフォルトでは標準のweb_searchツールだけを使用可能とする。 */
            l_tools := json_array_t(); 
            l_tool  := json_object_t();
            l_tool.put('type', 'web_search'); 
            l_tools.append(l_tool); 
            l_request_json.put('tools', l_tools);
        end if;
    end if;
    /*
    * Reasoningモデルであれば、effortをlowにする。 
    * 使用するモデルはgpt-6-astra, gpt-6-sol, gpt-6-lunaを想定している。
    * これらのモデルでは、すべてeffortを指定可能。
    */
    l_reasoning := json_object_t(); 
    l_reasoning.put('mode', 'standard'); -- standardで固定。[standard,pro]
    l_reasoning.put('effort', 'low');    -- lowで固定。     [none,minimal,low,medium,high,xhigh,max]
    l_reasoning.put('summary', 'auto');  -- autoで固定。    [auto,concise,detailed]
    l_request_json.put('reasoning', l_reasoning); 
    /*  
    * ユーザー・プロンプトの指定 
    */ 
    l_input     := json_array_t(); 
    l_input_obj := json_object_t(); 
    /*  
    * p_instructionsの指定があれば、developerロールのメッセージとして追加。 
    */ 
    if p_instructions is not null then 
        l_input_obj.put('role', 'developer'); 
        l_input_obj.put('content', p_instructions); 
        l_input.append(l_input_obj); 
        l_input_obj := json_object_t(); 
    end if; 
    /* 
    * ユーザー・ロールのメッセージを追加。
    */ 
    l_input_obj.put('role', 'user'); 
    l_input_obj.put('content', p_input); 
    l_input.append(l_input_obj); 
    l_request_json.put('input', l_input); 
    /* 送信するメッセージ */ 
    l_request := l_request_json.to_clob(); 
    apex_debug.info('request = %s', dbms_lob.substr(l_request, C_LOG_MESSAGE_MAX, 1));

    /*
    * ツール呼び出しの実行要求があれば、メッセージの送信を繰り返す。
    */
    l_tool_call_count := 0;
    if p_response_id is null then
        /* 初回クエスト時にコレクションを初期化する */
        apex_collection.create_or_truncate_collection(C_COLLECTION_NAME);
    end if;

    <<response_loop>>
    while l_request is not null
    loop
        /* ツール呼び出しの繰り返しを制限する。 */
        if l_tool_call_count >= C_TOOL_CALL_MAX then
            raise_application_error(-20002, 'Max tool call exceeded. ' || C_TOOL_CALL_MAX);
        end if;
        l_tool_call_count := l_tool_call_count + 1;

        /* OpenAIのResponses APIの呼び出し。 */ 
        apex_web_service.set_request_headers('Content-Type', 'application/json'); 
        l_response := apex_web_service.make_rest_request( 
            p_url => p_endpoint 
            ,p_http_method => 'POST' 
            ,p_body => l_request 
            ,p_credential_static_id => p_credential_static_id 
        ); 
        l_request := null;
        if apex_web_service.g_status_code <> 200 then 
            apex_debug.error(
                'HTTP status = %s, response prefix = %s'
                ,apex_web_service.g_status_code
                ,dbms_lob.substr(l_response, C_LOG_MESSAGE_MAX, 1)
            ); 
            raise_application_error(
                -20001
                ,'OpenAI API failed. HTTP = ' || apex_web_service.g_status_code
            );
        end if;
        apex_debug.info('response = %s', dbms_lob.substr(l_response, C_LOG_MESSAGE_MAX,1)); 
        l_response_json := json_object_t(l_response); 
        /* objectはつねにresponseとなるはずで、とくに参照しない。 */
        l_object := l_response_json.get_string('object');

        /* レスポンス処理の開始。 */
        p_status := l_response_json.get_string('status');
        p_incomplete_reason := null;
        p_error_code        := null;
        p_error_message     := null;
        l_tool_inputs := json_array_t();
        l_has_final_message := false;
        l_refusal := null;

        /* リクエストが失敗してない場合は会話を継続するidを保持する。 */
        if p_status in ('completed', 'incomplete') then
            p_response_id   := l_response_json.get_string('id'); 
        end if;

        if p_status = 'incomplete' then
            l_incomplete_details :=
                l_response_json.get_object('incomplete_details');
            if l_incomplete_details is not null then
                p_incomplete_reason :=
                    l_incomplete_details.get_string('reason');
            end if;
        elsif p_status = 'failed' then
            l_error := l_response_json.get_object('error');
            if l_error is not null then
                p_error_code    := l_error.get_string('code');
                p_error_message := l_error.get_string('message');
            end if;
        end if;
        /* usageの取り出し。きちんと確認するにはAPEXコレクションに書き出す必要がある。 */
        l_usage  := l_response_json.get_object('usage'); 
        /* outputの取り出し */ 
        l_output := l_response_json.get_array('output'); 
        l_output_size := l_output.get_size(); 
        apex_debug.info('output length = %s', l_output_size); 
        l_output_text := ''; 
        l_annotations := json_array_t(); 
        l_summary_text := '';
        for i in 1..l_output_size 
        loop 
            l_output_obj := treat(l_output.get(i-1) as json_object_t); 
            l_output_obj_type   := l_output_obj.get_string('type'); 
            l_output_obj_status := l_output_obj.get_string('status'); 
            /* 
            * outputのtypeごとの処理。 
            * -- message: 入力プロンプトに対するレスポンス - 人が読む。
            * -- reasoning: 推論の過程。
            * -- program: Programmatic Tool Callingのために生成されたコード。
            * -- function_call: モデルから要求されたツール呼び出し。
            */ 
            if l_output_obj_type = 'message' then 
                l_output_obj_role   := l_output_obj.get_string('role');
                /* 
                * ツール呼び出しの終了条件を確認する。
                * phaseが省略された通常の回答も対象。
                * commentaryは途中経過なので、最終回答としない。
                */
                if l_output_obj_role = 'assistant'
                    and l_output_obj_status = 'completed'
                    and nvl(l_output_obj.get_string('phase'), 'final_answer') = 'final_answer'
                then
                    l_has_final_message := true;
                end if;

                /* contentの取り出し */ 
                l_content := l_output_obj.get_array('content'); 
                l_content_size := l_content.get_size(); 
                apex_debug.info('content length = %s', l_content_size); 
                for j in 1..l_content_size 
                loop 
                    l_content_obj := treat(l_content.get(j-1) as json_object_t); 
                    l_content_obj_type := l_content_obj.get_string('type'); 
                    if l_content_obj_type = 'output_text' then 
                        l_output_text := l_output_text || l_content_obj.get_clob('text'); 
                        apex_debug.info('output_text = %s', dbms_lob.substr(l_output_text, C_LOG_MESSAGE_MAX, 1)); 
                        l_annotations_single := l_content_obj.get_array('annotations'); 
                        if l_annotations_single is not null then 
                            l_annotations.append_all(l_annotations_single); 
                        end if;
                    elsif l_content_obj_type = 'refusal' then
                        l_refusal := l_refusal || l_content_obj.get_clob('refusal'); 
                    end if; 
                end loop;
            elsif l_output_obj_type = 'reasoning' then
                l_summary := l_output_obj.get_array('summary');
                l_summary_size := l_summary.get_size();
                for j in 1..l_summary_size
                loop
                    l_summary_obj := treat(l_summary.get(j-1) as json_object_t);
                    l_summary_obj_type := l_summary_obj.get_string('type');
                    if l_summary_obj_type = 'summary_text' then
                        if l_summary_text is not null then
                            l_summary_text := l_summary_text || apex_application.CRLF;
                        end if;
                        l_summary_text := l_summary_text || l_summary_obj.get_clob('text');
                        apex_debug.info('summry_text = %s', dbms_lob.substr(l_summary_text, C_LOG_MESSAGE_MAX, 1));
                        /* APEXコレクションへのログ出力 */
                        apex_collection.add_member(
                            C_COLLECTION_NAME
                            ,p_c001 => l_output_obj_type
                            ,p_c002 => l_output_obj_status
                            ,p_c003 => 'summary_text'
                            ,p_clob001 => l_summary_text
                        );             
                    end if;
                end loop;
            elsif l_output_obj_type = 'program' then
                l_program_code := l_output_obj.get_clob('code');
                apex_debug.info(
                    'Program call_id = %s, code prefix = %s',
                    l_output_obj.get_string('call_id'),
                    dbms_lob.substr(l_program_code, C_LOG_MESSAGE_MAX, 1)
                );
                /* APEXコレクションへのログ出力 */
                apex_collection.add_member(
                    C_COLLECTION_NAME
                    ,p_c001 => l_output_obj_type
                    ,p_c002 => l_output_obj_status
                    ,p_c003 => 'code'
                    ,p_clob001 => l_program_code
                );             
            elsif l_output_obj_type = 'function_call' and p_status = 'completed' then
                /* ツール呼び出しの対応 */
                l_tool_call_id  := l_output_obj.get_string('call_id');
                l_function_name := l_output_obj.get_string('name');
                l_function_args := l_output_obj.get_clob('arguments');
                /* directの場合はcallerは含まない。 */
                l_tool_caller   := l_output_obj.get_object('caller');
                if l_tool_caller is not null then
                    l_tool_caller_string := l_tool_caller.to_string();
                else
                    l_tool_caller_string := '';
                end if;
                /* APEXコレクションへのログ出力 */
                apex_collection.add_member(
                    C_COLLECTION_NAME
                    ,p_c001 => l_output_obj_type
                    ,p_c002 => l_output_obj_status
                    ,p_c003 => l_tool_call_id
                    ,p_c004 => l_function_name
                    ,p_c005 => l_tool_caller_string
                    ,p_clob001 => l_function_args
                );
                /*
                * ストアド・プロシージャを動的に呼び出す。
                */
                select count(*) into l_function_exist from openai_tools
                where tool_set = p_tool_set and tool_type = 'function' and tool_name = l_function_name;
                if l_function_exist = 0 then
                    raise_application_error(
                        -20005, 'Invalid function is requested to call: ' || l_function_name
                    );
                end if;
                if dbms_lob.getlength(l_function_args) > 1000 then
                    raise_application_error(
                        -20006,
                        'Function argument is too long. Length = '
                        || dbms_lob.getlength(l_function_args)
                        || ' characters; maximum = 1000.'
                    );
                end if;
                apex_debug.info(
                    'Calling %s with %s',
                    l_function_name,
                    dbms_lob.substr(l_function_args, C_LOG_MESSAGE_MAX, 1)
                );
                l_dynamic_sql := 'begin :a := ' || l_function_name || '(:b); end;';
                execute immediate l_dynamic_sql using in out l_function_out, l_function_args;
                /* APEXコレクションへのログ出力 */
                apex_collection.add_member(
                    C_COLLECTION_NAME
                    ,p_c001 => l_output_obj_type
                    ,p_c002 => l_output_obj_status
                    ,p_c003 => l_tool_call_id
                    ,p_c004 => l_function_name
                    ,p_c005 => l_tool_caller_string
                    ,p_clob001 => l_function_out
                );
                /* リクエストの組み立て */
                l_tool_input := json_object_t();
                l_tool_input.put('type','function_call_output');
                l_tool_input.put('call_id', l_tool_call_id);
                l_tool_input.put('output', l_function_out);
                if l_tool_caller is not null then
                    l_tool_input.put('caller', l_tool_caller);
                end if;
                l_tool_inputs.append(l_tool_input);
            end if;
        end loop;
        /* 異常終了時は、新しいリクエストを送らない。 */
        exit response_loop when p_status in ('failed', 'incomplete');

        /* このサンプルは同期実行を前提とする */
        if p_status is null or p_status <> 'completed' then
            raise_application_error(
                -20003,
                'Unexpected response status: ' || nvl(p_status, 'NULL')
            );
        end if;

        /* 関数結果を返す必要がなく、最終回答も届いていれば終了 */
        exit response_loop when l_tool_inputs.get_size() = 0 and l_has_final_message;

        /*
        * ここに来るのは次のどちらか：
        * 1. 関数の実行結果を返す
        * 2. 最終回答がまだなので、空のinputで継続する
        */
        l_request_json := json_object_t();
        l_request_json.put('model', p_model);
        l_request_json.put('previous_response_id', p_response_id);

        if l_tools is not null then
            l_request_json.put('tools', l_tools);
        end if;

        l_request_json.put('reasoning', l_reasoning);
        l_request_json.put('input', l_tool_inputs);

        l_request := l_request_json.to_clob();

        apex_debug.info(
            'Continuation request = %s',
            dbms_lob.substr(l_request, C_LOG_MESSAGE_MAX, 1)
        );        
    end loop;

    p_output_text  := l_output_text;
    p_refusal      := l_refusal;
    p_summary_text := l_summary_text;
    if l_annotations is not null then
        p_annotations := l_annotations.to_clob();
    end if;
    if l_usage is not null then
        p_usage       := l_usage.to_string(); 
    end if;
end openai_responses_api;
/ 