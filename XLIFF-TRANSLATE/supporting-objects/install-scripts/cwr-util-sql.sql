create or replace package CWR_UTIL as
/*
表CWR_XLIFF_FILESのXLIFF_SOURCEとして保存されているXLIFFファイルを
APEXコレクションに取り込む。
*/
procedure load_from_source (
    p_id in number
    , p_source_lang out varchar2
    , p_target_lang out varchar2
    , p_collection_name in varchar2 default 'TRANSLATE'
);

/*
表CWR_XLIFF_FILESのXLIFF_RESULTとして保存されているXLIFFファイルを
APEXコレクションに取り込む。
*/
procedure load_from_result (
    p_id in number
    , p_source_lang out varchar2
    , p_target_lang out varchar2
    , p_collection_name in varchar2 default 'TRANSLATE'
);

/*
APEXコレクションに保持されている翻訳結果をXLIFF_SOURCEに適用し、
XLIFF_RESULTに保存する。
*/
procedure store_as_result (
    p_id in number
    , p_collection_name in varchar2 default 'TRANSLATE'
);

/*
APEXコレクションに保持されている翻訳前の文字列を、表CWR_MESSAGESの
内容を使って、一括で翻訳する。
*/
procedure batch_translate (
    p_source_lang in varchar2
    , p_target_lang in varchar2
    , p_collection_name in varchar2 default 'TRANSLATE'
);
end;
/

create or replace package body cwr_util
as

/*
XLIFFファイルよりsource_langとtarget_langを取り出す。
*/
procedure get_source_and_target_lang(
    p_xmlDoc in dbms_xmldom.domdocument
    ,p_source_lang out varchar2
    ,p_target_lang out varchar2 
)
as
    l_attrs      dbms_xmldom.domnamednodemap;
begin
    /* file要素の属性より、ソース言語とターゲット言語を取得する。 */
    l_attrs := dbms_xmldom.getAttributes(
        dbms_xmldom.item(
            dbms_xmldom.getElementsByTagName(p_xmlDoc, 'file'), 
        0)
    );
    p_source_lang := dbms_xmldom.getNodeValue(
        dbms_xmldom.getNamedItem(l_attrs, 'source-language')
    );
    p_target_lang := dbms_xmldom.getNodeValue(
        dbms_xmldom.getNamedItem(l_attrs, 'target-language')
    );
end get_source_and_target_lang;

/*
BLOBとして渡されるXLIFF（XML）から、翻訳前の文字列と翻訳済みの文字列から
APEXコレクションを作成する。
*/
procedure load_from_blob (
    p_blob              in blob -- XLIFFの内容
    , p_source_lang     out varchar2
    , p_target_lang     out varchar2
    , p_collection_name in varchar2
)
as
    l_xml        xmltype;
    l_xmlDoc     dbms_xmldom.domdocument;
    l_transUnits dbms_xmldom.domnodelist;
    l_transUnit  dbms_xmldom.domelement;
    l_id           varchar2(80);
    l_source_text  cwr_messages.message_text%type;
    l_target_text  cwr_messages.message_text%type;
begin
    /* BLOBよりDOMとして操作可能なXML文書を作成する。 */
    l_xml := xmltype.createXML(p_blob, NLS_CHARSET_ID('AL32UTF8'), null);
    l_xmlDoc := dbms_xmldom.newDOMDocument(l_xml);
    get_source_and_target_lang(
        p_xmlDoc => l_xmlDoc
        ,p_source_lang => p_source_lang
        ,p_target_lang => p_target_lang
    );
    /* XMLに含まれるtrans-unitの要素を全て取り出し、APEXコレクションに投入する。 */
    apex_collection.create_or_truncate_collection(p_collection_name);
    l_transUnits := dbms_xmldom.getElementsByTagName(l_xmlDoc, 'trans-unit');
    for i in 0..dbms_xmldom.getlength(l_transUnits)-1
    loop
        l_transUnit := dbms_xmldom.makeElement(
            dbms_xmldom.item(l_transUnits,i)
        );
        -- trans-unitのidを取り出す。
        l_id := dbms_xmldom.getAttribute(l_transUnit, 'id');
        -- trans-unitに含まれる要素source（翻訳対象の文字列）の値を取り出す。
        l_source_text := dbms_xmldom.getNodeValue(
            dbms_xmldom.getFirstChild(
                dbms_xmldom.item(
                    dbms_xmldom.getChildrenByTagName(l_transUnit, 'source'),
                    0
                )
            )
        );
        -- trans-unitに含まれる要素target（翻訳済みの文字列）の値を取り出す。
        l_target_text := dbms_xmldom.getNodeValue(
            dbms_xmldom.getFirstChild(
                dbms_xmldom.item(
                    dbms_xmldom.getChildrenByTagName(l_transUnit, 'target'),
                    0
                )
            )
        );
        -- 取り出した値をAPEXコレクションに保存する。
        apex_collection.add_member(
            p_collection_name => p_collection_name
            , p_c001 => l_id
            , p_c002 => l_source_text
            , p_c003 => l_target_text
        );
    end loop;
end load_from_blob;

procedure load_from_source(
    p_id in number
    , p_source_lang out varchar2
    , p_target_lang out varchar2
    , p_collection_name in varchar2
)
as
    l_blob blob;
begin
    /* 列XLIFF_SOURCEからAPEXコレクションを作成する。 */
    select xliff_source into l_blob from cwr_xliff_files where id = p_id;
    load_from_blob(
        p_blob => l_blob
        , p_source_lang => p_source_lang
        , p_target_lang => p_target_lang
        , p_collection_name => p_collection_name
    );
end load_from_source;

procedure load_from_result(
    p_id in number
    , p_source_lang out varchar2
    , p_target_lang out varchar2
    , p_collection_name in varchar2
)
as
    l_blob blob;
begin
    /* 列XLIFF_RESULTからAPEXコレクションを作成する。 */
    select xliff_result into l_blob from cwr_xliff_files where id = p_id;
    load_from_blob(
        p_blob => l_blob
        , p_source_lang => p_source_lang
        , p_target_lang => p_target_lang
        , p_collection_name => p_collection_name
    );
end load_from_result;

procedure store_as_result (
    p_id in number
    , p_collection_name in varchar2
)
as
    l_xml  xmltype;
    l_blob blob;
    l_blob_result blob;
    l_xmlDoc dbms_xmldom.domdocument;
    l_source_lang varchar2(80);
    l_target_lang varchar2(80);
    l_transUnits dbms_xmldom.domnodelist;
    l_transUnit  dbms_xmldom.domelement;
    l_id           varchar2(80);
    l_target     dbms_xmldom.domnode;
    l_target_text  cwr_messages.message_text%type;
begin
    /* XLIFF_SOURCEを取り出し、一時LOBにコピーした上でDOMを生成する。 */
    select xliff_source into l_blob from cwr_xliff_files where id = p_id;
    dbms_lob.createtemporary(l_blob_result, true);
    dbms_lob.copy(
        dest_lob => l_blob_result
        , src_lob => l_blob
        , amount => dbms_lob.lobmaxsize
    );
    l_xml := xmltype.createXML(l_blob_result, NLS_CHARSET_ID('AL32UTF8'), null);
    l_xmlDoc := dbms_xmldom.newDOMDocument(l_xml);
    get_source_and_target_lang(
        p_xmlDoc => l_xmlDoc
        ,p_source_lang => l_source_lang
        ,p_target_lang => l_target_lang
    );
    /* ソースとなるXLIFFのtrans-unitを全て取り出し、APEXコレクションに保持されている翻訳済み
     * 文字列でtargetを置き換える。
     */
    l_transUnits := dbms_xmldom.getElementsByTagName(l_xmlDoc, 'trans-unit');
    for i in 0..dbms_xmldom.getlength(l_transUnits)-1
    loop
        l_transUnit := dbms_xmldom.makeElement(
            dbms_xmldom.item(l_transUnits,i)
        );
        l_id := dbms_xmldom.getAttribute(l_transUnit, 'id');
        select c003 into l_target_text from apex_collections where collection_name = p_collection_name and c001 = l_id;
        l_target := dbms_xmldom.getFirstChild(
            dbms_xmldom.item(
                dbms_xmldom.getChildrenByTagName(l_transUnit, 'target'),
                0
            )
        );
        dbms_xmldom.setNodeValue(l_target, l_target_text);
    end loop;
    /* 置き換えたDOMをBLOBに変換し、XLIFF_RESULTに保存する。 */
    update cwr_xliff_files 
    set xliff_result           = l_xml.getblobval(NLS_CHARSET_ID('AL32UTF8'))
        ,xliff_result_filename = 
            replace(xliff_source_filename,'.xlf','_translated.xlf')
        ,xliff_result_mimetype = xliff_source_mimetype 
        ,xliff_result_charset  = xliff_source_charset
        ,xliff_result_lastupd  = sysdate
        ,source_lang = l_source_lang
        ,target_lang = l_target_lang        
    where id = p_id;
end store_as_result;

procedure batch_translate(
    p_source_lang in varchar2
    , p_target_lang in varchar2
    , p_collection_name in varchar2
)
as
    l_target_text  cwr_messages.message_text%type;
begin
    /* APEXコレクションのC002 - 翻訳対象文字列 - に一致する文字列を表CWR_MESSAGESより探し、
     * 一致する文字列があれば、その翻訳結果でC003 - 翻訳済み文字列 - を置き換える。
     * 翻訳対象文字列に複数の翻訳済み文字列が存在する場合は（選択する基準がないので）、最初に見つけた
     * 結果を採用する。
     */
    for c in (select seq_id, c001, c002 from apex_collections where collection_name = p_collection_name)
    loop
        begin
            /* 翻訳済み文字列を探す。 */
            select t.message_text into l_target_text
            from cwr_messages s join cwr_messages t on s.name = t.name
            where s.message_language = p_source_lang
            and t.message_language = p_target_lang
            and s.message_text = c.c002
            order by s.name fetch first 1 rows only;
            /* APEXコレクションのC003のみを更新する。 */
            apex_collection.update_member_attribute(
                p_collection_name => p_collection_name
                , p_seq => c.seq_id
                , p_attr_number => 3
                , p_attr_value => l_target_text   
            );
        exception
            when others then
                null; -- 翻訳文が見つからなければ、何も変更しない。
        end;
    end loop;
end batch_translate;   
end cwr_util;
/