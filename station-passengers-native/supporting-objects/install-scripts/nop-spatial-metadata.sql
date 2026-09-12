-- Exact spatial metadata snapshot. Existing metadata is never overwritten.
declare
    l_count number;
    l_srid number;
    l_dims mdsys.sdo_dim_array;
begin
    if sys_context('USERENV','CURRENT_SCHEMA') <> 'APEXDEV' then
        raise_application_error(-20001, 'Installation requires APEXDEV and TBS_APEXDEV.');
    end if;
    select count(*) into l_count from user_sdo_geom_metadata
    where table_name='NOP_PASSENGERS' and column_name='GEOM';
    if l_count=0 then
        insert into user_sdo_geom_metadata(table_name,column_name,diminfo,srid)
        values ('NOP_PASSENGERS','GEOM',mdsys.sdo_dim_array(
            mdsys.sdo_dim_element('LONGITUDE',-180,180,0.005),
            mdsys.sdo_dim_element('LATITUDE',-90,90,0.005)),6668);
        commit;
    else
        select srid,diminfo into l_srid,l_dims from user_sdo_geom_metadata
        where table_name='NOP_PASSENGERS' and column_name='GEOM';
        if l_srid is null or l_srid<>6668 or l_dims.count<>2 then
            raise_application_error(-20002,'Spatial metadata differs; no changes made.');
        end if;
        for i in 1..2 loop
            if nvl(l_dims(i).sdo_dimname,'?')<>case i when 1 then 'LONGITUDE' else 'LATITUDE' end
               or nvl(l_dims(i).sdo_lb,0)<>case i when 1 then -180 else -90 end
               or nvl(l_dims(i).sdo_ub,0)<>case i when 1 then 180 else 90 end
               or nvl(l_dims(i).sdo_tolerance,0)<>0.005 then
                raise_application_error(-20002,'Spatial metadata differs; no changes made.');
            end if;
        end loop;
    end if;
end;
/