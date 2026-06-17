drop view wr_menus_vl;
drop table wr_menus_tl purge;
drop table wr_menus    purge;

create table wr_menus (
    id        number       primary key,
    menu_name varchar2(80) not null,
    volume    varchar2(16) not null,
    price     number       not null
);

create table wr_menus_tl (
    id              number       primary key,
    menu_id         number       not null,
    local_menu_name varchar2(80) not null,
    language        varchar2(3)  not null
);

create or replace view wr_menus_vl (id, menu_name, volume, price)
as
select
    o.id
   ,l.local_menu_name menu_name
   ,o.volume
   ,o.price
from wr_menus o join wr_menus_tl l on o.id = l.menu_id
where l.language = sys_context('USERENV','LANG');

insert into wr_menus(id, menu_name, volume, price) values(1,'牛丼','ミニ盛',350);
insert into wr_menus(id, menu_name, volume, price) values(2,'ジャージャー麺','並盛',650);
insert into wr_menus(id, menu_name, volume, price) values(3,'ハンバーガー','大盛',700);
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(1,1,'牛丼','JA');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(2,1,'beef bowl','US');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(3,1,'牛肉碗','ZHS');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(4,1,'소고기덮밥','KO');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(5,2,'ジャージャー麺','JA');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(6,2,'Fried Source Noodles','US');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(7,2,'炸醬麵','ZHS');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(8,2,'짜장면','KO');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(9,3,'ハンバーガー','JA');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(10,3,'hamburger','US');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(11,3,'汉堡包','ZHS');
insert into wr_menus_tl(id, menu_id, local_menu_name, language) values(12,3,'햄버거','KO');
commit;
/
