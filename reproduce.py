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
PeapodsInvariant.leverageManager_initializePosition(7512210835434651725905099472056434341739178813352756821300091440887536255535,445293)
    PeapodsInvariant.lendingAssetVault_donate(29,260218220366325374329009571257842978230743268132344612098122129154253)
    PeapodsInvariant.pod_bond(9,708169,76,27834936219280075976105146659374430575719420700338582208687038070918632517068)
    PeapodsInvariant.leverageManager_addLeverage(22615495116313877241008256206703797993050352229327933012155595010433805893,2272428169609714065864534120908149823866128401439346332716424670606754161180,23241241420107297813623728481742245240836074647044829146793039553531380274)
    PeapodsInvariant.leverageManager_addLeverage(626723379169146919250103014150575918349215409951618580963270351376012473,24570796619690053863417182543086801377536778155111475010369583155972830378717,363149704192382652030279174044104370770659596683568049415617924095075396482)
    PeapodsInvariant.leverageManager_removeLeverage(14317,11128,41565229920034335551826642214029897121620160476487848270418840341522459401910,3570852386722911754843567193361227770588467982323224863648600121280778971)
    PeapodsInvariant.leverageManager_addLeverage(36061998385886488890420887927728985478455295812458901768325205364950640455,375693905573877554299384318903856527306691199437435637259395767175056270681,0)
    *wait* Time delay: 13 seconds Block delay: 218
    PeapodsInvariant.fraxPair_repayAsset(1010932060483077060357907978077105428329697038479442835164040693719087770,0,13646713,5474)
    PeapodsInvariant.invariant_POD_12()
        """
solidity_code = convert_to_solidity(call_sequence)
print(solidity_code)