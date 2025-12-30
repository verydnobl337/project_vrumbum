-- Этап 1. Создание и заполнение БД

-- Создание схемы raw_data:
create schema if not exists raw_data;

-- Создание таблицы sales в raw_data:
create table if not exists raw_data.sales (
	id INTEGER,
	auto TEXT,
	gasoline_consumption NUMERIC,
	price NUMERIC,
	date DATE,
	person_name TEXT,
	phone TEXT,
	discount INTEGER,
	brand_origin TEXT
);

-- Заполняю таблицу sales данными через psql:
\copy raw_data.sales(id, auto, gasoline_consumption, price, date, person_name, phone, discount, brand_origin) FROM 'C:/Users/adond/AppData/Local/Temp/cars.csv' DELIMITER ',' CSV HEADER NULL 'null';

-- Создание схемы car_shop:
create schema if not exists car_shop;

-- Создание таблицы cars:
create table car_shop.cars (
    id SERIAL primary key, /* Автоинкремент, уникальный идентификатор машины */
    brand VARCHAR not null, /* Название бренда может содержать буквы и цифры */
    model VARCHAR not null, /* Модель может содержать буквы и цифры */
    gasoline_consumption NUMERIC(5,2), /* Расход топлива с точностью до сотых, может быть NULL */
    price NUMERIC(9,2) not null /* Цена до 9 цифр с двумя знаками после запятой */
);

-- Создание таблицы colors:
create table car_shop.colors (
	id SERIAL primary key, /* Автоинкремент, уникальный идентификатор цвета */
	color_name VARCHAR not null unique /* Название цвета, уникальное значение */
);

-- Создание таблицы car_colors со связью многие-ко-многим:
create table car_shop.car_colors (
	car_id INTEGER not null references car_shop.cars(id) on delete cascade, /* При удалении машины удаляются её цвета в car_colors */
	color_id INTEGER not null references car_shop.colors(id) on delete cascade, /* При удалении цвета удаляются связанные записи в car_colors */
	primary key (car_id, color_id) /* Первичный ключ для уникальной пары */
);

-- Создание таблицы customers:
create table car_shop.customers (
	id SERIAL primary key, /* Автоинкремент, уникальный идентификатор покупателя */
	name VARCHAR not null, /* Имя покупателя */
	phone VARCHAR(50) unique null /* Телефон, может быть NULL */
);

-- Создание таблицы sales_clean:
create table car_shop.sales_clean (
	id SERIAL primary key, /* Автоинкремент, уникальный идентификатор продажи */
	car_id INTEGER not null references car_shop.cars(id), /* Ссылка на машину */
	customer_id INTEGER not null references car_shop.customers(id), /* Ссылка на покупателя */
	date DATE not null, /* Дата продажи */
	discount INTEGER /* Скидка, может быть NULL */
);

-- Заполняю таблицу cars:
insert into car_shop.cars (brand, model, gasoline_consumption, price)
select distinct /* Уникальные машины */
	-- В raw_data.sales поле auto содержит марку, модель и цвет разделяем их: 
	split_part(trim(split_part(auto, ',', 1)), ' ', 1) as brand,
    substr(trim(split_part(auto, ',', 1)), length(split_part(trim(split_part(auto, ',', 1)), ' ', 1)) + 2) as model,
    gasoline_consumption,
    price
from raw_data.sales;

-- Заполняю таблицу colors:
insert into car_shop.colors (color_name)
/* Достаем цвет из поля auto */
select distinct trim(split_part(auto, ',', 2)) as color_name
from raw_data.sales
where auto like '%,%';

-- Заполняю таблицу car_colors:
insert into car_shop.car_colors (car_id, color_id)
select DISTINCT
    c.id,
    co.id
from raw_data.sales s
join car_shop.cars c 
    on c.brand = split_part(trim(split_part(s.auto, ',', 1)), ' ', 1)
   and c.model = substr(
        trim(split_part(s.auto, ',', 1)),
        length(split_part(trim(split_part(s.auto, ',', 1)), ' ', 1)) + 2
   )
   and (
        c.gasoline_consumption = s.gasoline_consumption
        or (c.gasoline_consumption IS NULL and s.gasoline_consumption IS NULL)
   )
   and c.price = s.price 
join car_shop.colors co 
    on co.color_name = trim(split_part(s.auto, ',', 2))
where s.auto LIKE '%,%';

-- Заполняю таблицу customers:
insert into car_shop.customers (name, phone)
select distinct 
	person_name as name,
	phone
from raw_data.sales;

-- Заполняю таблицу sales_clean:
insert into car_shop.sales_clean (car_id, customer_id, date, discount)
select
    c.id,
    cu.id,
    s.date,
    s.discount
from raw_data.sales s
join car_shop.cars c
    on c.brand = split_part(trim(split_part(s.auto, ',', 1)), ' ', 1)
   and c.model = substr(
        trim(split_part(s.auto, ',', 1)),
        length(split_part(trim(split_part(s.auto, ',', 1)), ' ', 1)) + 2
   )
   and (
        c.gasoline_consumption = s.gasoline_consumption
        or (c.gasoline_consumption IS NULL and s.gasoline_consumption IS NULL)
   )
   and c.price = s.price
join car_shop.customers cu
    on cu.name = s.person_name
   and (cu.phone = s.phone or (cu.phone IS NULL and s.phone IS NULL));


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
	c.brand brand_name,
	EXTRACT(year from sc.date) sale_year,
	ROUND(AVG(c.price * (1 - COALESCE(sc.discount, 0)/100.0)), 2) AS price_avg
from car_shop.cars c
join car_shop.sales_clean sc on (c.id = sc.car_id)
group by 
	c.brand,
	EXTRACT(year from sc.date)
order by
	c.brand,
	sale_year;

---- Задание 3. Посчитайте среднюю цену всех автомобилей с разбивкой по месяцам в 2022 году с учётом скидки.
select
	EXTRACT(month from sc.date) as month,
	EXTRACT(year from sc.date) as sale_year,
	ROUND(AVG(c.price * (1 - COALESCE(sc.discount, 0)/100.0)), 2) AS price_avg
from car_shop.cars c
join car_shop.sales_clean sc on (c.id = sc.car_id)
where EXTRACT(year from sc.date) = '2022'
group by
	EXTRACT(month from sc.date),
	EXTRACT(year from sc.date)
order by
	month;

---- Задание 4. Напишите запрос, который выведет список купленных машин у каждого пользователя.
select
	cu.name as person,
	STRING_AGG(c.brand || ' ' || c.model, ', ') as cars
from car_shop.sales_clean sc
join car_shop.customers cu on (sc.customer_id = cu.id)
join car_shop.cars c on (sc.car_id = c.id)
group by cu.name
order by cu.name;

---- Задание 5. Наибольшая и наименьшая цены продажи авто с разбивкой по стране без скидки.
select
    brand_origin,
    MAX(price) as price_max,
    MIN(price) as price_min
from raw_data.sales
group by brand_origin
order by brand_origin;

---- Задание 6. Кол-во всех пользователей из США.
select
    COUNT(*) as persons_from_usa_count
from car_shop.customers
where phone LIKE '+1%';




