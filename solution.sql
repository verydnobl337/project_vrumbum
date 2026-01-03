-- Этап 1. Создание и заполнение БД

-- Создание схемы raw_data:
create schema if not exists raw_data;
-- Создание таблицы sales в raw_data:
create table if not exists raw_data.sales (
    id integer,
    auto text,
    gasoline_consumption numeric,
    price numeric,
    date date,
    person_name text,
    phone text,
    discount integer,
    brand_origin text
);
-- Заполняю таблицу sales данными через psql:
\copy raw_data.sales(id, auto, gasoline_consumption, price, date, person_name, phone, discount, brand_origin) FROM 'C:/Users/adond/AppData/Local/Temp/cars.csv' DELIMITER ',' CSV HEADER NULL 'null';
-- Создание схемы car_shop:
create schema if not exists car_shop;
-- Создание таблицы countries:
create table car_shop.countries (
    id serial primary key,
    country_name text not null unique
);
-- Заполняю таблицу countries:
insert into car_shop.countries (country_name)
/* Обработаю также "пустые" cтраны */
select distinct coalesce(brand_origin, 'Unknown')
from raw_data.sales s
where not exists (
    select 1 from car_shop.countries c
    where c.country_name = coalesce(s.brand_origin, 'Unknown')
);
-- Создание таблицы brands:
create table car_shop.brands (
    id serial primary key,
    brand_name text not null unique,
    country_id integer not null references car_shop.countries(id)
);
-- Заполняю таблицу brands:
insert into car_shop.brands (brand_name, country_id)
/* Обработаю также "пустые" бренды */
select distinct
    coalesce(split_part(trim(split_part(s.auto, ',', 1)), ' ', 1), 'Unknown'),
    c.id
from raw_data.sales s
join car_shop.countries c
    on c.country_name = coalesce(s.brand_origin, 'Unknown')
where not exists (
    select 1 from car_shop.brands b
    where b.brand_name = coalesce(split_part(trim(split_part(s.auto, ',', 1)), ' ', 1), 'Unknown')
);
-- Создание таблицы cars:
create table car_shop.cars (
    id serial primary key,
    brand_id integer not null references car_shop.brands(id),
    model text not null,
    gasoline_consumption numeric(5,2)
);
-- Заполняю таблицу cars:
insert into car_shop.cars (brand_id, model, gasoline_consumption)
select distinct
    b.id,
    substr(
        trim(split_part(s.auto, ',', 1)),
        length(split_part(trim(split_part(s.auto, ',', 1)), ' ', 1)) + 2
    ),
    s.gasoline_consumption
from raw_data.sales s
join car_shop.brands b
    on b.brand_name = coalesce(split_part(trim(split_part(s.auto, ',', 1)), ' ', 1), 'Unknown')
where not exists (
    select 1 from car_shop.cars c
    join car_shop.brands b2 on b2.id = c.brand_id
    where c.model = substr(trim(split_part(s.auto, ',', 1)), length(split_part(trim(split_part(s.auto, ',', 1)), ' ', 1)) + 2)
      and b2.id = b.id
);
-- Создание таблицы colors:
create table car_shop.colors (
    id serial primary key,
    color_name text not null unique
);
-- Заполняю таблицу colors:
insert into car_shop.colors (color_name)
/* Обработаю также "пустые" цвета */
select distinct coalesce(trim(split_part(auto, ',', 2)), 'Unknown')
from raw_data.sales s
where not exists (
    select 1 from car_shop.colors c
    where c.color_name = coalesce(trim(split_part(s.auto, ',', 2)), 'Unknown')
);
-- Создание таблицы car_colors:
create table car_shop.car_colors (
    id serial primary key,
    car_id integer not null references car_shop.cars(id) on delete cascade,
    color_id integer not null references car_shop.colors(id),
    unique (car_id, color_id)
);
-- Заполняю таблицу car_colors:
insert into car_shop.car_colors (car_id, color_id)
select distinct
    c.id,
    co.id
from raw_data.sales s
join car_shop.cars c
    on c.model = substr(trim(split_part(s.auto, ',', 1)), length(split_part(trim(split_part(s.auto, ',', 1)), ' ', 1)) + 2)
join car_shop.colors co
    on co.color_name = coalesce(trim(split_part(s.auto, ',', 2)), 'Unknown')
where not exists (
    select 1 from car_shop.car_colors cc
    where cc.car_id = c.id and cc.color_id = co.id
);
-- Создание таблицы customers:
create table car_shop.customers (
    id serial primary key,
    name text not null,
    phone text unique
);
-- Заполняю таблицу customers:
insert into car_shop.customers (name, phone)
select distinct person_name, phone
from raw_data.sales s
where not exists (
    select 1 from car_shop.customers cu
    where cu.name = s.person_name and (cu.phone = s.phone or (cu.phone is null and s.phone is null))
);  
-- Создание таблицы sales_clean:
create table car_shop.sales_clean (
    id serial primary key,
    car_color_id integer not null references car_shop.car_colors(id),
    customer_id integer not null references car_shop.customers(id),
    sale_date date not null,
    price numeric(9,2) not null,
    discount integer check (discount between 0 and 100)
);
-- Заполняю таблицу sales_clean:
insert into car_shop.sales_clean (car_color_id, customer_id, sale_date, price, discount)
select
    cc.id,
    cu.id,
    s.date,
    s.price,
    s.discount
from raw_data.sales s
join car_shop.cars c
    on c.model = substr(trim(split_part(s.auto, ',', 1)), length(split_part(trim(split_part(s.auto, ',', 1)), ' ', 1)) + 2)
join car_shop.colors co
    on co.color_name = coalesce(trim(split_part(s.auto, ',', 2)), 'Unknown')
join car_shop.car_colors cc
    on cc.car_id = c.id and cc.color_id = co.id
join car_shop.customers cu
    on cu.name = s.person_name
   and (cu.phone = s.phone or (cu.phone is null and s.phone is null));

-- Этап 2. Создание выборок

---- Задание 1. Напишите запрос, который выведет процент моделей машин, у которых нет параметра `gasoline_consumption`.
select
    ROUND(
        COUNT(*) * 100.0 / (select COUNT(*) from car_shop.cars),
        2
    ) AS nulls_percentage_gasoline_consumption
from car_shop.cars
where gasoline_consumption IS NULL;
---- Задание 2. Напишите запрос, который покажет название бренда и среднюю цену его автомобилей в разбивке по всем годам с учётом скидки.
select 
    b.brand_name,
    extract(year from sc.sale_date) as sale_year,
    round(avg(sc.price), 2) as price_avg
from car_shop.sales_clean sc
join car_shop.car_colors cc on cc.id = sc.car_color_id
join car_shop.cars c on c.id = cc.car_id
join car_shop.brands b on b.id = c.brand_id
group by 
    b.brand_name,
    extract(year from sc.sale_date)
order by
    b.brand_name,
    sale_year;
---- Задание 3. Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки.
select
    extract(month from sc.sale_date) as month,
    round(avg(sc.price), 2) as price_avg
from car_shop.sales_clean sc
join car_shop.car_colors cc on cc.id = sc.car_color_id
join car_shop.cars c on c.id = cc.car_id
where extract(year from sc.sale_date) = 2022
group by
    extract(month from sc.sale_date)
order by
    month;
---- Задание 4. Напишите запрос, который выведет список купленных машин у каждого пользователя.
select
    cu.name as person,
    string_agg(b.brand_name || ' ' || c.model, ', ') as cars
from car_shop.sales_clean sc
join car_shop.customers cu on (sc.customer_id = cu.id)
join car_shop.car_colors cc on (sc.car_color_id = cc.id)
join car_shop.cars c on (cc.car_id = c.id)
join car_shop.brands b on (c.brand_id = b.id)
group by cu.name
order by cu.name;
---- Задание 5. Наибольшая и наименьшая цены продажи авто с разбивкой по стране без скидки.
select
    co.country_name as brand_origin,
    round(max(sc.price / (1 - coalesce(sc.discount, 0)/100.0)), 2) as price_max,
    round(min(sc.price / (1 - coalesce(sc.discount, 0)/100.0)), 2) as price_min
from car_shop.sales_clean sc
join car_shop.car_colors cc
    on sc.car_color_id = cc.id
join car_shop.cars c
    on cc.car_id = c.id
join car_shop.brands b
    on c.brand_id = b.id
join car_shop.countries co
    on b.country_id = co.id
group by co.country_name
order by co.country_name;
---- Задание 6. Кол-во всех пользователей из США.
select
    COUNT(*) as persons_from_usa_count
from car_shop.customers
where phone LIKE '+1%';




