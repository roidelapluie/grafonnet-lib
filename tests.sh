#!/bin/sh

x=0

for i in `find . -name '*.jsonnet' -or -name '*.libsonnet'`
do
    t="Formating $i..."
    if jsonnet fmt --test -n 4 $i;
    then
        echo $t OK
    else
        echo $t NOK
        x=1
    fi
done

for i in tests/*/*.jsonnet examples/*.jsonnet
do
    json=$(dirname $i)/$( basename $i .jsonnet )_test_output.json
    json_e=$(dirname $i)/$( basename $i .jsonnet )_compiled.json
    t="Compiling $i..."
    if jsonnet  -J . $i > $json
    then
        echo $t OK
    else
        echo $t NOK
        x=1
        continue
    fi

    if [[ $1 == "update" ]]; then cp $json $json_e; fi

    t="Checking $i..."
    if diff -urt $json $json_e
    then
        echo $t OK
    else
        echo $t NOK
        x=1
    fi
done

if [[ -z RUN_DOCKER_ACCEPTANCE_TESTS ]]
then
    exit $x
fi

# Isolate compiled examples to test them in grafana

cp examples/*_compiled.json tests/acceptance/dashboards
# Launch a grafana instance

docker run -d -p 3000:3000 --name grafana-acc -v $PWD/tests/acceptance:/provisioning -e GF_AUTH_ANONYMOUS_ENABLED=true -e GF_PATHS_PROVISIONING=/provisioning grafana/grafana:master

# Wait for grafana to be up
until curl 127.0.0.1:3000; do sleep 1; done
sleep 1

# test the dashboards
for d in tests/acceptance/dashboards/*.json
do
    slug=$(basename $d|cut -d _ -f 1)
    t="Testing $slug"
    curl http://127.0.0.1:3000/api/dashboards/db/$slug |jsonnet fmt -|jsonnet - > $d.GET
    (cat $d.GET; echo " + {meta:[], dashboard+: {version:1,id:null}}")|jsonnet fmt - |jsonnet - > $d.processed
    (echo "{dashboard:"; cat $d; echo " + {version:1,id:null}} + {meta:[]}")|jsonnet fmt - |jsonnet - > $d.pretty
    if diff -urt $d.pretty $d.processed
    then
        echo $t OK
    else
        echo $t OK
        x=1
    fi
done

read
docker kill grafana-acc
docker rm grafana-acc

exit $x
