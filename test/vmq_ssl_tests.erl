-module(vmq_ssl_tests).
-include_lib("eunit/include/eunit.hrl").
-export([setup_c/0, connect_cert_auth_expired/1]).

-define(setup(F), {setup, fun setup/0, fun teardown/1, F}).
-define(listener(Port), {{{127,0,0,1}, Port}, [{mountpoint, ""},
                                               {cafile, "../test/ssl/all-ca.crt"},
                                               {certfile, "../test/ssl/server.crt"},
                                               {keyfile, "../test/ssl/server.key"},
                                               {tls_version, tlsv1}]}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Tests Descriptions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
ssl_test_() ->
    [
     {"Check SSL Connection no auth",
      ?setup(fun connect_no_auth/1)}
    ,{"Check SSL Connection no auth wrong CA",
      ?setup(fun connect_no_auth_wrong_ca/1)}
    ,{"Check SSL Connection Cert Auth",
      {setup, fun setup_c/0, fun teardown/1, fun connect_cert_auth/1}}
    ,{"Check SSL Connection Cert Auth Without",
      {setup, fun setup_c/0, fun teardown/1, fun connect_cert_auth_without/1}}
    ,{"Check SSL Connection Cert Auth Expired",
      {setup, fun setup_c/0, fun teardown/1, fun connect_cert_auth_expired/1}}
    ,{"Check SSL Connection Cert Auth Revoked",
      {setup, fun setup_r/0, fun teardown/1, fun connect_cert_auth_revoked/1}}
    ,{"Check SSL Connection Cert Auth with CRL Check",
      {setup, fun setup_r/0, fun teardown/1, fun connect_cert_auth_crl/1}}
    ,{"Check SSL Connection using Identity from Cert",
      {setup, fun setup_i/0, fun teardown/1, fun connect_identity/1}}
    ,{"Check SSL Connection using Identity from Cert, but no Client Cert provided",
      {setup, fun setup_i/0, fun teardown/1, fun connect_no_identity/1}}
    ].

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Setup Functions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
setup() ->
    vmq_test_utils:setup(),
    {ok, _} = vmq_server_cmd:set_config(allow_anonymous, true),
    {ok, _} = vmq_server_cmd:listener_start(1888, [{ssl, true},
                                                   {nr_of_acceptors, 5},
                                                   {cafile, "../test/ssl/all-ca.crt"},
                                                   {certfile, "../test/ssl/server.crt"},
                                                   {keyfile, "../test/ssl/server.key"},
                                                   {tls_version, tlsv1}]),
    ok.

setup_c() ->
    vmq_test_utils:setup(),
    {ok, _} = vmq_server_cmd:set_config(allow_anonymous, true),
    {ok, _} = vmq_server_cmd:listener_start(1888, [{ssl, true},
                                                   {nr_of_acceptors, 5},
                                                   {cafile, "../test/ssl/all-ca.crt"},
                                                   {certfile, "../test/ssl/server.crt"},
                                                   {keyfile, "../test/ssl/server.key"},
                                                   {tls_version, "tlsv1.2"},
                                                   {require_certificate, true}]),
    ok.

setup_r() ->
    vmq_test_utils:setup(),
    {ok, _} = vmq_server_cmd:set_config(allow_anonymous, true),
    {ok, _} = vmq_server_cmd:listener_start(1888, [{ssl, true},
                                                   {nr_of_acceptors, 5},
                                                   {cafile, "../test/ssl/all-ca.crt"},
                                                   {certfile, "../test/ssl/server.crt"},
                                                   {keyfile, "../test/ssl/server.key"},
                                                   {tls_version, "tlsv1.2"},
                                                   {require_certificate, true},
                                                   {crlfile, "../test/ssl/crl.pem"}]),
    ok.

setup_i() ->
    vmq_test_utils:setup(),
    {ok, _} = vmq_server_cmd:set_config(allow_anonymous, false),
    {ok, _} = vmq_server_cmd:listener_start(1888, [{ssl, true},
                                                   {nr_of_acceptors, 5},
                                                   {cafile, "../test/ssl/all-ca.crt"},
                                                   {certfile, "../test/ssl/server.crt"},
                                                   {keyfile, "../test/ssl/server.key"},
                                                   {tls_version, "tlsv1.2"},
                                                   {require_certificate, true},
                                                   {crlfile, "../test/ssl/crl.pem"},
                                                   {use_identity_as_username, true}]),
    ok.

teardown(_) ->
    vmq_test_utils:teardown().

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Actual Tests
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
load_cacerts() ->
    IntermediateCA = "../test/ssl/test-signing-ca.crt",
    RootCA = "../test/ssl/test-root-ca.crt",
    load_cert(RootCA) ++ load_cert(IntermediateCA).

load_cert(Cert) ->
    {ok, Bin} = file:read_file(Cert),
    case filename:extension(Cert) of
        ".der" ->
            %% no decoding necessary
            [Bin];
        _ ->
            %% assume PEM otherwise
            Contents = public_key:pem_decode(Bin),
            [DER || {Type, DER, Cipher} <-
                    Contents, Type == 'Certificate',
                    Cipher == 'not_encrypted']
    end.




connect_no_auth(_) ->
    Connect = packet:gen_connect("connect-success-test", [{keepalive, 10}]),
    Connack = packet:gen_connack(0),
    {ok, SSock} = ssl:connect("localhost", 1888,
                              [binary, {active, false}, {packet, raw},
                               {cacerts, load_cacerts()},
                               {versions, [tlsv1]}]),
    ok = ssl:send(SSock, Connect),
    ok = packet:expect_packet(ssl, SSock, "connack", Connack),
    ?_assertEqual(ok, ssl:close(SSock)).

connect_no_auth_wrong_ca(_) ->
    assert_error_or_closed({error,{tls_alert,"unknown ca"}},
                  ssl:connect("localhost", 1888,
                              [binary, {active, false}, {packet, raw},
                               {verify, verify_peer},
                               {cacertfile, "../test/ssl/test-alt-ca.crt"},
                               {versions, [tlsv1]}])).

connect_cert_auth(_) ->
    Connect = packet:gen_connect("connect-success-test", [{keepalive, 10}]),
    Connack = packet:gen_connack(0),
    {ok, SSock} = ssl:connect("localhost", 1888,
                              [binary, {active, false}, {packet, raw},
                               {verify, verify_peer},
                               {cacerts, load_cacerts()},
                               {certfile, "../test/ssl/client.crt"},
                               {keyfile, "../test/ssl/client.key"}]),
    ok = ssl:send(SSock, Connect),
    ok = packet:expect_packet(ssl, SSock, "connack", Connack),
    ?_assertEqual(ok, ssl:close(SSock)).

connect_cert_auth_without(_) ->
    assert_error_or_closed({error,{tls_alert,"handshake failure"}},
                  ssl:connect("localhost", 1888,
                              [binary, {active, false}, {packet, raw},
                               {verify, verify_peer},
                               {cacerts, load_cacerts()}])).

connect_cert_auth_expired(_) ->
    assert_error_or_closed({error,{tls_alert,"certificate expired"}},
                  ssl:connect("localhost", 1888,
                              [binary, {active, false}, {packet, raw},
                               {verify, verify_peer},
                               {cacerts, load_cacerts()},
                               {certfile, "../test/ssl/client-expired.crt"},
                               {keyfile, "../test/ssl/client.key"}])).

connect_cert_auth_revoked(_) ->
    assert_error_or_closed({error,{tls_alert,"certificate revoked"}},
                  ssl:connect("localhost", 1888,
                              [binary, {active, false}, {packet, raw},
                               {verify, verify_peer},
                               {cacerts, load_cacerts()},
                               {certfile, "../test/ssl/client-revoked.crt"},
                               {keyfile, "../test/ssl/client.key"}])).

connect_cert_auth_crl(_) ->
    Connect = packet:gen_connect("connect-success-test", [{keepalive, 10}]),
    Connack = packet:gen_connack(0),
    {ok, SSock} = ssl:connect("localhost", 1888,
                              [binary, {active, false}, {packet, raw},
                               {verify, verify_peer},
                               {cacerts, load_cacerts()},
                               {certfile, "../test/ssl/client.crt"},
                               {keyfile, "../test/ssl/client.key"}]),
    ok = ssl:send(SSock, Connect),
    ok = packet:expect_packet(ssl, SSock, "connack", Connack),
    ?_assertEqual(ok, ssl:close(SSock)).

connect_identity(_) ->
    Connect = packet:gen_connect("connect-success-test", [{keepalive, 10}]),
    Connack = packet:gen_connack(0),
    {ok, SSock} = ssl:connect("localhost", 1888,
                              [binary, {active, false}, {packet, raw},
                               {verify, verify_peer},
                               {cacerts, load_cacerts()},
                               {certfile, "../test/ssl/client.crt"},
                               {keyfile, "../test/ssl/client.key"}]),
    ok = ssl:send(SSock, Connect),
    ok = packet:expect_packet(ssl, SSock, "connack", Connack),
    ?_assertEqual(ok, ssl:close(SSock)).

connect_no_identity(_) ->
    assert_error_or_closed({error,{tls_alert,"handshake failure"}},
                  ssl:connect("localhost", 1888,
                              [binary, {active, false}, {packet, raw},
                               {verify, verify_peer},
                               {cacerts, load_cacerts()}])).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Helper
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-compile({inline, [assert_error_or_closed/2]}).
assert_error_or_closed(Error, Val) ->
    ?_assertEqual(case Val of
                      {error, closed} -> true;
                      Error -> true;
                      {ok, SSLSocket} = E ->
                          ssl:close(SSLSocket),
                          E;
                      Other -> Other
                  end, true).
