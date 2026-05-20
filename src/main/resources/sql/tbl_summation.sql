create table tbl_summation (
    id bigint generated always as identity primary key,
    record_id bigint not null,
    text text,
    created_datetime timestamp not null default now(),
    constraint fk_record_summation foreign key (record_id)
    references tbl_video_recoding (id)
);