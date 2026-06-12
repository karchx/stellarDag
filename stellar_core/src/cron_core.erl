-module(cron_core).
-export([next_interval_ms/1]).

-record(cron, {m_mask, h_mask, d_mask, mo_mask, dw_mask}).

next_interval_ms(CronBin) ->
    Cron = parse_cron(CronBin),
    Now = calendar:universal_time(),
    
    %% Trunc seconds
    {Date, {Hour, Min, _}} = Now,
    StartDt = advance_minute({Date, {Hour, Min, 0}}),

    NextDt = find_next_datetime(StartDt, Cron),

    NowSecs = calendar:datetime_to_gregorian_seconds(Now),
    NextSecs = calendar:datetime_to_gregorian_seconds(NextDt),
    (NextSecs - NowSecs) * 1000.

parse_cron(CronBin) ->
    [MBin, HBin, DBin, MoBin, DwBin] = binary:split(CronBin, <<" ">>, [global, trim_all]),
    #cron{
        m_mask  = parse_part(MBin, 0, 59),
        h_mask  = parse_part(HBin, 0, 23),
        d_mask  = parse_part(DBin, 1, 31),
        mo_mask = parse_part(MoBin, 1, 12),
        dw_mask = parse_part(DwBin, 1, 7)
    }.

parse_part(<<"*">>, Min, Max) ->
    build_mask(Min, Max, 1);
parse_part(<<"*/", StepBin/binary>>, Min, Max) ->
    build_mask(Min, Max, binary_to_integer(StepBin));
parse_part(ValBin, _, _) ->
    1 bsl binary_to_integer(ValBin).

%% calculate with <<
build_mask(Min, Max, Step) ->
    lists:foldl(fun(V, Acc) -> Acc bor (1 bsl V) end, 0, lists:seq(Min, Max, Step)).

%% mask_cron & (1 << Value) != 0
is_valid(Value, Mask) ->
    (Mask band (1 bsl Value)) =/= 0.

is_valid_day(Y, Mo, D, Cron) ->
    Dw = calendar:day_of_the_week(Y, Mo, D),
    is_valid(D, Cron#cron.d_mask) andalso is_valid(Dw, Cron#cron.dw_mask).

find_next_datetime({{Y, Mo, D}, {H, M, _}}, Cron) ->
    case step(Y, Mo, D, H, M, Cron) of
        {Y, Mo, D, H, M} -> {{Y, Mo, D}, {H, M, 0}};
        {NY, NMo, ND, NH, NM} -> find_next_datetime({{NY, NMo, ND}, {NH, NM, 0}}, Cron)
    end.

step(Y, Mo, _D, _H, _M, _Cron) when Mo > 12 ->
    {Y + 1, 1, 1, 0, 0};
step(Y, Mo, D, H, M, Cron) ->
    case is_valid(Mo, Cron#cron.mo_mask) of
        false -> {Y, Mo + 1, 1, 0, 0};
        true ->
            MaxD = calendar:last_day_of_the_month(Y, Mo),
            if
                D > MaxD -> {Y, Mo + 1, 1, 0, 0};
                true ->
                    case is_valid_day(Y, Mo, D, Cron) of
                        false -> {Y, Mo, D + 1, 0, 0};
                        true ->
                            if
                                H > 23 -> {Y, Mo, D + 1, 0, 0};
                                true ->
                                    case is_valid(H, Cron#cron.h_mask) of
                                        false -> {Y, Mo, D, H + 1, 0};
                                        true ->
                                            if
                                                M > 59 -> {Y, Mo, D, H + 1, 0};
                                                true ->
                                                    case is_valid(M, Cron#cron.m_mask) of
                                                        false -> {Y, Mo, D, H, M + 1};
                                                        true -> {Y, Mo, D, H, M} %% return fixed point
                                                    end
                                            end
                                    end
                            end
                    end
            end
    end.

advance_minute(Dt) ->
    Secs = calendar:datetime_to_gregorian_seconds(Dt),
    calendar:gregorian_seconds_to_datetime(Secs + 60).

