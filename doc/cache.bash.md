cache.bash
==========

Interaction with cloud based systems may take time necessary to interact with remote services. To optimise time of subsequent invocations of the same source, reading from services should be done together with caching mechanism. cache.bash provides invocation cache for bash based systems. Supports data encryption.

Install
=======
```
git clone https://github.com/rstyczynski/oci-tools 2>/dev/null || (cd oci-tools; git pull)
source oci-tools/bin/cache.bash
```

Usage
=====

* cache.invoke cmd - use to invoke command cmd. Exit code comes from cmd

```
cache.invoke date
cache.invoke date
```

* cache.flush cmd - removes response data

```
cache.invoke date
cache.flush date
cache.invoke date
```

Cache is controlled by environment variables:

* cache\_ttl                      - response ttl in minutes. You may use fraction to set seconds; default: 60
* cache\_group                    - response group name; derived from cmd when not provided
* cache\_key                      - response key name; derived from cmd when not provided
* cache\_crypto\_key               - key used to encrypt/decrypt stored answer using opens ssl
* cache\_crypto\_cipher            - cipher used to encrypt/decrypt stored answer using opens ssl
* cache\_invoke\_filter            - command used to filter answer before storage
* cache\_response\_filter          - command used to filter answer before receiving from storage
* cache\_dir                      - cache directory; default: ~/.cache/cache_answer
* cache\_debug=no|yes              - debug flag; default: no
* cache\_warning=yes|no            - warning flag; default: yes
* cache\_progress=no|yes            - shows progress spinner; default: no

Facts
=====

1. Response data is kept in cache_dir/cache_group/cache_key file. Files are deleted after cache\_ttl minutes.
2. Cached response is stored with .info file having all information about cached data. 
3. Cache TTL i.e. time to live in minutes is specific for cache group, and stored in cache directory in .info file.
4. Each invocagtion of cache.invoke calls data eviction procedure cache.evict_group

Special use
===========
If you want to keep response data in well known path/file, you need to specify group and key name before invocation. This may be useful to create data repository to be used by other tools w/o need to invoke cache.invoke. Such model requires manual use of cache.evict_group. 

* cache.evict_group cmd               - removes old respose; controled by ttl
* cache_group=group cache.evict_group - removes all old data of given group
* cache.evict_group                   - removes all old data



Exemplary usage
===============

```
cache_ttl=0.08
cache_dir=~/greetings
cache_group=echo cache_key=hello cache.invoke echo hello

openssl genrsa -out $HOME/.ssh/cache_secret.pem 2048
cache_crypto_key=$HOME/.ssh/cache_secret.pem
cache_group=echo cache_key=world cache.invoke echo world

ls -l ~/greetings
ls -la ~/greetings/echo 

cat ~/greetings/echo/.info

cat ~/greetings/echo/hello
cat ~/greetings/echo/hello.info

cat ~/greetings/echo/world
cat ~/greetings/echo/world.info

sleep 6
cache_dir=~/greetings
cat ~/greetings/echo/.info

ls -la ~/greetings/echo
cache_group=echo cache.evict_group
ls -la ~/greetings/echo

rm -rf ~/greetings
```

-
==========
cache.bash 1.1 by ryszard.styczynski@oracle.com is part of oci-tools, available at https://github.com/rstyczynski/oci-tools

