# MTL

This is an implementation of MTL in Erlang. See
http://rfc.zeromq.org/spec:11 for the specification of MTL.

## Building and running

    $ git clone https://github.com/squaremo/mtl.git
    $ cd mtl
    $ ./rebar get-deps
    $ ./rebar compile

    $ erl +K -pa deps/erlzmq/ebin ebin -s mtl
