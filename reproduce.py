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
PeapodsInvariant.pod_bond(78112753206398527664743652120203638163535903155754636407556138131943906962,96148718453766611458661370746811976370821397389877714922062641916,6188251556393622199277182340625269634063071737645774958822901683171,67889186762179505860347332941167706472327806621920886873698582212651580)
    PeapodsInvariant.leverageManager_initializePosition(3381502326864871928010088963155146576789420193651300363008071,0)
    PeapodsInvariant.lendingAssetVault_deposit(1,33056247646586375450483427190004353713541210084544250712,87364126624905488179878085014559191155881809769089458952418185128417)
    PeapodsInvariant.leverageManager_addLeverage(1,2872389689410624781507887018093070221080700916185582748321871960,1355545775063989851619007092110204159721320145)
    PeapodsInvariant.leverageManager_removeLeverage(135534222491379842860839797270837178241151579484726987384821,22774044323390086469675898022364841826019419854881419245,8639527331269158195381959001724440307714794960910344842065)
        """
solidity_code = convert_to_solidity(call_sequence)
print(solidity_code)