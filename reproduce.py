import re


def convert_to_solidity(call_sequence):
    # Regex patterns to extract the necessary parts
    call_pattern = re.compile(
        r"(?:Fuzz\.)?(\w+\([^\)]*\))(?: from: (0x[0-9a-fA-F]{40}))?(?: Gas: (\d+))?(?: Time delay: (\d+) seconds)?(?: Block delay: (\d+))?"
    )
    wait_pattern = re.compile(
        r"\*wait\*(?: Time delay: (\d+) seconds)?(?: Block delay: (\d+))?"
    )

    solidity_code = "function test_replay() public {\n"

    lines = call_sequence.strip().split("\n")
    last_index = len(lines) - 1

    for i, line in enumerate(lines):
        call_match = call_pattern.search(line)
        wait_match = wait_pattern.search(line)
        if call_match:
            call, from_addr, gas, time_delay, block_delay = call_match.groups()

            # Add prank line if from address exists
            if from_addr:
                solidity_code += f'    vm.prank({from_addr});\n'

            # Add warp line if time delay exists
            if time_delay:
                solidity_code += f"    vm.warp(block.timestamp + {time_delay});\n"

            # Add roll line if block delay exists
            if block_delay:
                solidity_code += f"    vm.roll(block.number + {block_delay});\n"

            if "collateralToMarketId" in call:
                continue

            # Add function call
            if i < last_index:
                solidity_code += f"    try this.{call} {{}} catch {{}}\n"
            else:
                solidity_code += f"    {call};\n"
            solidity_code += "\n"
        elif wait_match:
            time_delay, block_delay = wait_match.groups()

            # Add warp line if time delay exists
            if time_delay:
                solidity_code += f"    vm.warp(block.timestamp + {time_delay});\n"

            # Add roll line if block delay exists
            if block_delay:
                solidity_code += f"    vm.roll(block.number + {block_delay});\n"
            solidity_code += "\n"

    solidity_code += "}\n"

    return solidity_code


# Example usage
call_sequence = """
PeapodsInvariant.pod_bond(2120090275729578767995570985877644431815598909241605069899276006228971667173,3,125794286822449229810673629584966884005866434201929614206365549147058169228,4551153641069476745631989853008149581361482388018538635811026423301750758)
    PeapodsInvariant.pod_addLiquidityV2(11280242260666790340641056095499319217872169502276416281197860575853296105480,6542767889324732794921268052957195513188927438024485270012650300600765989107,2558265612301423993763294367343340187229770091824731067323829188717326869,411)
    PeapodsInvariant.stakingPool_stake(591509929466372188963208937724749541271771514899585537,29362635244798088429903519241463388948736390552623754910923220383983,6140448846260877993935657411324514837401860438571)
    PeapodsInvariant.aspTKN_mint(13485202529540624030675376284779167588194906969110491592701650633840006597,23894152686175610449648448580161837585054442570620465691183099349049147789,896326885741304058930463213788912448944035525939732387143338730233323331315,6068754)
    *wait* Time delay: 31 seconds Block delay: 2
    PeapodsInvariant.stakingPool_stake(120634022500685195823109955806256731280684297465568951152957,87608942731984508501451623781891939898755232304715075225309991912051,3451729170513406135580746403653413014704327)
    PeapodsInvariant.aspTKN_mint(394452666779336493558504377559870358158422018858563422015226091711231710508,36295840955239858238997988139099707520739020859402862424072010837319172,884748360839903012084705192829400473827930797917518399254316622879156368207,20815)
    PeapodsInvariant.aspTKN_mint(357544348030787784384091619515244840702723466732566393480541068079065330,13741417074310372535539447514260385204363637655293854305751116378,1273483049505563406766041186525855358480819554722278504608222216113486750171,25)
        """
solidity_code = convert_to_solidity(call_sequence)
print(solidity_code)