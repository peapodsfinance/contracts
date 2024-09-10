#!/bin/bash
while [ $# -gt 0 ]; do
  if [[ $1 == *"--"* ]]; then
    v="${1/--/}"
    declare $v="$2"
  fi

  shift
done

# Check if bytecodeFile exists
if [ -z "$bytecodeHash" ]
then
  echo "Bytecode not found. Provide the correct bytecode after the command."
  exit 1
fi


output=$(cast create2 --jobs 12 --case-sensitive --matching "0x6B175474E89094C44Da98b954EedeAC495271d0F" --init-code-hash $bytecodeHash --deployer $deployer)

salt=$(echo "$output" | grep "Salt:" | awk '{print $2}' | tr -d '\n' | sed 's/\r//g')

printf "%s" "$salt"