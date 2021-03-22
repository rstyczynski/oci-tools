#!/bin/bash


iptables_save=$1


# iptables table: https://rlworkman.net/howtos/iptables/chunkyhtml/c962.html
#                 https://gist.github.com/mcastelino/c38e71eb0809d1427a6650d843c42ac2
#

interpret_conditions=no # keep it no at this time. TODO
print_empty_targets=0   # print target call even when it's empty

#
# prepare variables
# 
rm -f edges.log 
rm -f nodes.log
rm -f *.chains

unset tables
declare -A tables

unset return;stack

#
#
#

indent=0
dots='...............................................................................................................................................................'
function say() {
  if [ $indent -gt 0 ]; then
    echo $dots | cut -b1-$indent | tr -d '\n'
  fi

  echo $@
}

 function execute_chain() {
    local ipsec_chain=$1

    if [ "$ipsec_chain" != "$prev_chain" ]; then
      say "=========================================="
      say "=== EXECUTE: $table :: $ipsec_chain"
      say "=========================================="
    fi

    local prev_chain=$ipsec_chain

    steps=$(say ${!tables[@]} | tr ' ' '\n' | egrep "^${table};${ipsec_chain};step;\d+" | sort -n -t';' -k4 | cut -d';' -f4 | sort -un)
    for current_step in $steps; do

      local jump_type=${tables[${table};${ipsec_chain};step;${current_step};then]}
      local jump_destination=${tables[${table};${ipsec_chain};step;${current_step};destination]}


      if [ "${tables[${table};${jump_destination}]}" = known ] || [ $print_empty_targets -eq 1 ] || [ "${tables[${table};${jump_destination}]}" = system ]; then
        say "step: $current_step: $jump_type to $jump_destination | ${tables[${table};step;${current_step}]}"

        # TODO - conditions
        # 

        case $jump_type in
          goto)
            #say "GOTO: $jump_destination"
            indent=$(( $indent + 5 ))
            execute_chain $jump_destination
            indent=$(( $indent - 5 ))
            # TODO goto means direct execution to a new place, and never go back. So if table finishes and destination - do not continue here. Just finish the chain.
            # to implement this it's needed to understand conditions, and run the table for given set of coditions
            if [ "$interpret_conditions" = yes ]; then
              break
            fi
            ;;

          jump)
            #say "CALL: $jump_destination"
            # TODO - remember current step
            indent=$(( $indent + 5 ))
            execute_chain $jump_destination
            indent=$(( $indent - 5 ))
            # TODO goto oen step after
            ;;
        esac
      fi
    done
  }


# main tables

tables=$(cat $iptables_save | grep '^*' | cut -f2 -d'*')

for table in $tables; do
  
  say '============================'
  say "Processing $table"
  say '============================'

  createNode $table

  # set regular targets
  for target in RETURN ACCEPT DNAT SNAT DROP REJECT LOG ULOG MARK MASQUERADE REDIRECT; do
    tables[${table};${target}]=system
  done

  # discover known chains
  IFS='
'
  for ipsec_line in $(cat $iptables_save | sed -n "/^\*$table/,/COMMIT/p" | egrep -v "^COMMIT$|^#|^$|^:|^\*$table"); do
    ipsec_cmd=$(say $ipsec_line | cut -d' ' -f1 )
    case $ipsec_cmd in
    -A)
      ipsec_chain=$(say $ipsec_line | cut -d' ' -f2)
      say $ipsec_chain >> $table.chains.tmp
    esac
  done
  cat $table.chains.tmp | sort -u > $table.chains
  rm $table.chains.tmp
  cat $table.chains

  tables[${table};chains]=$(cat $table.chains)

  IFS='
'
  for ipsec_line in $(cat $iptables_save | sed -n "/^\*$table/,/COMMIT/p" | egrep -v "^COMMIT$|^#|^$|^:|^\*$table"); do
    ipsec_cmd=$(say $ipsec_line | cut -d' ' -f1 )
    case $ipsec_cmd in
    -A)
      ipsec_chain=$(say $ipsec_line | cut -d' ' -f2)

      tables[${table};${ipsec_chain}]=known

      tables[${table};stepNo]=$(( ${tables[${table};stepNo]} + 1 ))
      current_step=${tables[${table};stepNo]}
      
      # keep actual line for each step
      tables[${table};step;${current_step}]=$ipsec_line

      conditions=$(say $ipsec_line | tr -s ' ' | tr ' ' '\n' | sed -n "/$ipsec_chain/,/-[jg]/p" | egrep -v "^-[jg]|^$ipsec_chain" | tr '\n' ' ' | sed 's/ $/$/g')
      tables[${table};${ipsec_chain};step;${current_step};if]=$conditions

      goto=$(say $ipsec_line | tr -s ' ' | tr ' ' '\n' | sed -n "/-g/,/xxx/p" | tr '\n' ' ' | cut -f2 -d' ')
      if [ ! -z "$goto" ]; then
        options=$(say $ipsec_line | tr -s ' ' | tr ' ' '\n' | sed -n "/$goto/,/xxx/p"  | grep -v $goto | tr '\n' ' ')
        tables[${table};${ipsec_chain};step;${current_step};then]=goto
        tables[${table};${ipsec_chain};step;${current_step};destination]=$goto
        tables[${table};${ipsec_chain};step;${current_step};options]=$options
      else
        jump=$(say $ipsec_line | tr -s ' ' | tr ' ' '\n' | sed -n "/-j/,/xxx/p" | tr '\n' ' ' | cut -f2 -d' ')
        if [ ! -z "$jump" ]; then
          options=$(say $ipsec_line | tr -s ' ' | tr ' ' '\n' | sed -n "/$jump/,/xxx/p"  | grep -v $jump | tr '\n' ' ')
          tables[${table};${ipsec_chain};step;${current_step};then]=jump
          tables[${table};${ipsec_chain};step;${current_step};destination]=$jump
          tables[${table};${ipsec_chain};step;${current_step};options]=$options
        fi
      fi
      ;;
    *)
      say "Warning: UNKNOWN cmd: $ipsec_cmd at $ipsec_line"
      ;;
    esac
  done

  chains=$(say ${!tables[@]} | tr ' ' '\n' | egrep "^${table};\w+;step;\d+" | cut -d';' -f2 | sort -u)

  for ipsec_chain in $chains; do
    steps=$(say ${!tables[@]} | tr ' ' '\n' | egrep "^${table};${ipsec_chain};step;\d+" | sort -n -t';' -k4 | cut -d';' -f4 | sort -un)

    # keep note of steps for each chain on the table
    tables[${table};${ipsec_chain};steps]=$steps

    # print steps.
    for current_step in $steps; do
      say -n "${table}:${ipsec_chain}:$current_step:>>>>>"
      if [ ! -z "${tables[${table};${ipsec_chain};step;${current_step};if]}" ]; then
        say -n "When ${tables[${table};${ipsec_chain};step;${current_step};if]}, then ${tables[${table};${ipsec_chain};step;${current_step};then]} to ${table}:${tables[${table};${ipsec_chain};step;${current_step};destination]}"
      else
        say -n "${tables[${table};${ipsec_chain};step;${current_step};then]} to ${table}:${tables[${table};${ipsec_chain};step;${current_step};destination]}"
      fi

      if [ ! -z "${tables[${table};${ipsec_chain};step;${current_step};options]}" ]; then
        say " with ${tables[${table};${ipsec_chain};step;${current_step};options]}"
      else
        say ""
      fi
    done
  done

  #
  # execute table
  #

 
  # PREROUTING
  execute_chain PREROUTING

  # FORWARD
  execute_chain FORWARD

  # INPUT
  execute_chain INPUT

  # OUTPUT
  execute_chain OUTPUT

  # POSTROUTING
  execute_chain POSTROUTING

done

