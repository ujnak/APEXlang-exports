            create table ndmm_monuments (
                monument_id               varchar2
                (
                    9 char
                )
                not null,
                monument_name             varchar2
                (
                    100 char
                )
                not null,
                construction_year         varchar2
                (
                    50 char
                )
                ,
                location_description      varchar2
                (
                    200 char
                )
                not null,
                disaster_name             varchar2
                (
                    200 char
                )
                not null,
                disaster_type             varchar2
                (
                    100 char
                )
                not null,
                legacy_content            varchar2
                (
                    2000 char
                )
                not null,
                publication_date          date                not null,
                revision_publication_date varchar2
                (
                    100 char
                )
                ,
                restrictions              varchar2 (
                    500 char
                )
                ,
                geometry                  mdsys.sdo_geometry  not null,
                constraint ndmm_monuments_geom_ck check (
                    geometry.sdo_gtype = 2001
                    and geometry.sdo_srid = 4326
                )
                ,
                constraint ndmm_monuments_pk primary key (
                    monument_id
                )
            )
            ;

            insert into user_sdo_geom_metadata (
                table_name,
                column_name,
                diminfo,
                srid
            )
            values (
                'NDMM_MONUMENTS',
                'GEOMETRY',
                mdsys.sdo_dim_array (
                    mdsys.sdo_dim_element (
                        'LONGITUDE', -180, 180, 0.00001
                    )
                    ,
                    mdsys.sdo_dim_element (
                        'LATITUDE', -90, 90, 0.00001
                    )
                )
                ,
                4326
            )
            ;

            create index ndmm_monuments_sidx
            on ndmm_monuments (
                geometry
            )
            indextype is mdsys.spatial_index_v2
            parameters (
                'sdo_indx_dims=2'
            )
            ;

            commit;