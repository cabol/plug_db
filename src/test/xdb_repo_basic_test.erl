-module(xdb_repo_basic_test).

%% Common Test
-export([
  init_per_testcase/2,
  end_per_testcase/2
]).

%% Test Cases
-export([
  t_insert/1,
  t_insert_errors/1,
  t_insert_on_conflict/1,
  t_update/1,
  t_delete/1,
  t_get/1,
  t_get_by/1,
  t_all/1,
  t_all_with_pagination/1,
  t_delete_all/1,
  t_delete_all_with_conditions/1
]).

%% Helpers
-export([
  seed/1
]).

-import(xdb_ct, [assert_error/2]).

%%%===================================================================
%%% CT
%%%===================================================================

-spec init_per_testcase(atom(), xdb_ct:config()) -> xdb_ct:config().
init_per_testcase(_, Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),
  {ok, _} = Repo:start_link(),
  Config.

-spec end_per_testcase(atom(), xdb_ct:config()) -> xdb_ct:config().
end_per_testcase(_, Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),
  ok = xdb_repo_sup:stop(Repo),
  Config.

%%%===================================================================
%%% Test Cases
%%%===================================================================

-spec t_insert(xdb_ct:config()) -> ok.
t_insert(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  {ok, #{id := 1}} = Repo:insert(person:schema(#{id => 1})),

  #{id := 1, first_name := undefined} = Repo:get(person, 1),

  CS = xdb_changeset:change(person:schema(#{id => 2}), #{first_name => <<"Joe">>}),
  {ok, #{id := 2, first_name := <<"Joe">>}} = Repo:insert(CS),

  #{id := 2, first_name := <<"Joe">>} = Repo:get(person, 2),
  ok.

-spec t_insert_errors(xdb_ct:config()) -> ok.
t_insert_errors(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  ok = assert_error(fun() ->
    Repo:insert(account:schema(#{id => 1, username => "cabol"}))
  end, {no_exists, account}),

  ok = assert_error(fun() ->
    Repo:insert(person:schema(#{}))
  end, no_primary_key_value_error),

  {error, CS} =
    xdb_ct:pipe(#{id => 1}, [
      {fun person:schema/1, []},
      {fun xdb_changeset:change/2, [#{first_name => <<"Joe">>}]},
      {fun xdb_changeset:add_error/3, [first_name, <<"Invalid">>]},
      {fun Repo:insert/1, []}
    ]),

  ok = assert_error(fun() -> Repo:update(CS) end, badarg).

-spec t_insert_on_conflict(xdb_ct:config()) -> ok.
t_insert_on_conflict(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),
  ok = seed(Config),

  {ok, #{id := 1}} =
    Repo:insert(
      person:schema(#{id => 1, first_name => <<"FakeAlan">>}),
      [{on_conflict, nothing}]
    ),

  #{id := 1, first_name := <<"Alan">>} = Repo:get(person, 1),

  {ok, #{id := 1}} =
    Repo:insert(
      person:schema(#{id => 1, first_name => <<"FakeAlan">>}),
      [{on_conflict, replace}]
    ),

  #{id := 1, first_name := <<"FakeAlan">>} = Repo:get(person, 1),

  ok = assert_error(fun() ->
    Repo:insert(person:schema(#{id => 1}))
  end, conflict).

-spec t_update(xdb_ct:config()) -> ok.
t_update(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),
  ok = seed(Config),

  {ok, _CS} =
    xdb_ct:pipe(person, [
      {fun Repo:get/2, [1]},
      {fun person:changeset/2, [#{first_name => <<"Joe2">>}]},
      {fun Repo:update/1, []}
    ]),

  #{id := 1, first_name := <<"Joe2">>} = Repo:get(person, 1),

  ok = assert_error(fun() ->
    xdb_ct:pipe(#{id => 11}, [
      {fun person:schema/1, []},
      {fun person:changeset/2, [#{first_name => "other", last_name => "other", age => 33}]},
      {fun Repo:update/1, []}
    ])
  end, stale_entry_error).

-spec t_delete(xdb_ct:config()) -> ok.
t_delete(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  undefined = Repo:get(person, 1),
  ok = seed(Config),
  P1 = #{'__meta__' := _, id := 1} = Repo:get(person, 1),

  {ok, #{'__meta__' := _, id := 1}} = Repo:delete(P1),
  undefined = Repo:get(person, 1),

  {ok, #{id := 2}} =
    xdb_ct:pipe(#{id => 2}, [
      {fun person:schema/1, []},
      {fun xdb_changeset:change/2, [#{first_name => <<"Joe">>}]},
      {fun Repo:delete/1, []}
    ]),

  {error, #{}} =
    xdb_ct:pipe(#{id => 3}, [
      {fun person:schema/1, []},
      {fun xdb_changeset:change/2, [#{first_name => <<"Joe">>}]},
      {fun xdb_changeset:add_error/3, [first_name, <<"Invalid">>]},
      {fun Repo:delete/1, []}
    ]),

  ok = assert_error(fun() -> Repo:delete(P1) end, stale_entry_error).

-spec t_get(xdb_ct:config()) -> ok.
t_get(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),
  undefined = Repo:get(person, 1),
  ok = seed(Config),

  #{'__meta__' := _, id := 1} = Repo:get(person, 1),
  #{'__meta__' := _, id := 2} = Repo:get(person, 2),
  #{'__meta__' := _, id := 3} = Repo:get(person, 3),
  ok.

-spec t_get_by(xdb_ct:config()) -> ok.
t_get_by(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  [] = Repo:all(person),
  ok = seed(Config),

  #{id := 1} = Repo:get_by(person, [{id, 1}]),
  #{id := 2} = Repo:get_by(person, [{id, 2}]),
  #{id := 3} = Repo:get_by(person, [{id, 3}]),
  #{id := 3} = Repo:get_by(person, [{last_name, <<"Poe">>}]),
  #{id := 1} = Repo:get_by(person, [{first_name, <<"Alan">>}, {last_name, <<"Turing">>}]),

  ok = assert_error(fun() ->
    Repo:get_by(person, [{first_name, <<"Alan">>}])
  end, multiple_results_error).

-spec t_all(xdb_ct:config()) -> ok.
t_all(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  [] = Repo:all(person),
  ok = seed(Config),

  #{
    1 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Turing">>},
    2 := #{'__meta__' := _, first_name := <<"Charles">>, last_name := <<"Darwin">>},
    3 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Poe">>}
  } = All = person:list_to_map(Repo:all(person)),
  3 = maps:size(All),
  ok.

-spec t_all_with_pagination(xdb_ct:config()) -> ok.
t_all_with_pagination(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),
  ok = seed(Config),

  Expected = person:list_to_map(Repo:all(person)),

  [P1] = Repo:all(person, [{limit, 1}, {offset, 0}]),
  [P2] = Repo:all(person, [{limit, 1}, {offset, 1}]),
  [P3] = Repo:all(person, [{limit, 1}, {offset, 2}]),
  [P2, P3] = Repo:all(person, [{limit, 2}, {offset, 1}]),
  [] = Repo:all(person, [{limit, 1}, {offset, 3}]),
  [] = Repo:all(person, [{limit, 10}, {offset, 4}]),

  Expected = person:list_to_map([P1, P2, P3]),

  Query1 = xdb_query:new(person, [{age, '>', 100}]),
  [] = Repo:all(Query1, [{limit, 10}, {offset, 0}]),

  Query2 = xdb_query:new(person, [{age, '>', 40}]),
  #{
    1 := #{first_name := <<"Alan">>, last_name := <<"Turing">>},
    2 := #{first_name := <<"Charles">>, last_name := <<"Darwin">>}
  } = All = person:list_to_map(Repo:all(Query2, [{limit, 10}, {offset, 0}])),
  2 = maps:size(All),
  ok.

-spec t_delete_all(xdb_ct:config()) -> ok.
t_delete_all(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  [] = Repo:all(person),
  ok = seed(Config),

  #{
    1 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Turing">>},
    2 := #{'__meta__' := _, first_name := <<"Charles">>, last_name := <<"Darwin">>},
    3 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Poe">>}
  } = All = person:list_to_map(Repo:all(person)),
  3 = maps:size(All),

  {3, undefined} = Repo:delete_all(person),
  [] = Repo:all(person),

  ok = assert_error(fun() -> Repo:delete_all(account) end, {no_exists, account}).

-spec t_delete_all_with_conditions(xdb_ct:config()) -> ok.
t_delete_all_with_conditions(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  [] = Repo:all(person),
  ok = seed(Config),

  #{
    1 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Turing">>},
    2 := #{'__meta__' := _, first_name := <<"Charles">>, last_name := <<"Darwin">>},
    3 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Poe">>}
  } = All1 = person:list_to_map(Repo:all(person)),
  3 = maps:size(All1),

  Query1 = xdb_query:new(person, [{'and', [{first_name, <<"Alan">>}, {age, '>', 40}]}]),
  {1, [_]} = Repo:delete_all(Query1),

  #{
    2 := #{'__meta__' := _, first_name := <<"Charles">>, last_name := <<"Darwin">>},
    3 := #{'__meta__' := _, first_name := <<"Alan">>, last_name := <<"Poe">>}
  } = All2 = person:list_to_map(Repo:all(person)),
  2 = maps:size(All2),
  ok.

%%%===================================================================
%%% Helpers
%%%===================================================================

-spec seed(xdb_ct:config()) -> ok.
seed(Config) ->
  Repo = xdb_lib:keyfetch(repo, Config),

  People = [
    person:schema(#{id => 1, first_name => "Alan", last_name => "Turing", age => 41}),
    person:schema(#{id => 2, first_name => "Charles", last_name => "Darwin", age => 73}),
    person:schema(#{id => 3, first_name => "Alan", last_name => "Poe", age => 40})
  ],

  _ = [{ok, _} = Repo:insert(P) || P <- People],
  ok.