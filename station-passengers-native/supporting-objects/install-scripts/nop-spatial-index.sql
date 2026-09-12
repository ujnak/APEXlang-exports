-- DBMS_METADATA snapshot. Run after metadata; never rebuild existing indexes.
declare
    l_count number;
begin
    if sys_context('USERENV','CURRENT_SCHEMA') <> 'APEXDEV' then
        raise_application_error(-20001, 'Installation requires APEXDEV and TBS_APEXDEV.');
    end if;
    select count(*) into l_count from all_indexes
    where owner='APEXDEV' and index_name='NOP_PASSENGERS_SIDX';
    if l_count=0 then
        execute immediate q'~CREATE INDEX "APEXDEV"."NOP_PASSENGERS_SIDX" ON "APEXDEV"."NOP_PASSENGERS" ("GEOM")
   INDEXTYPE IS "MDSYS"."SPATIAL_INDEX_V2"  PARAMETERS ('layer_gtype=LINE')~';
    else
        select count(*) into l_count from all_indexes i
        where i.owner='APEXDEV' and i.index_name='NOP_PASSENGERS_SIDX'
          and i.table_owner='APEXDEV' and i.table_name='NOP_PASSENGERS'
          and i.ityp_owner='MDSYS' and i.ityp_name='SPATIAL_INDEX_V2'
          and trim(i.parameters)='layer_gtype=LINE'
          and i.status='VALID' and i.domidx_status='VALID' and i.domidx_opstatus='VALID'
          and (select count(*) from all_ind_columns c where c.index_owner=i.owner
               and c.index_name=i.index_name)=1
          and exists(select 1 from all_ind_columns c where c.index_owner=i.owner
               and c.index_name=i.index_name and c.column_name='GEOM');
        if l_count<>1 then
            raise_application_error(-20003,'Spatial index differs or is invalid; no changes made.');
        end if;
    end if;
end;
/