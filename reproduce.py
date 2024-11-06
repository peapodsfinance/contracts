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
PeapodsInvariant.pod_bond(2455,89063,2197,7359728031390065322374290399224949003757973631999763537425004526956656055445)
    PeapodsInvariant.pod_addLiquidityV2(11344,71499,32415571041978010960063235659160843094754525720062629458088219924499405610455,263551192347352786203763059376465822233999771205583638808680051835362958)
    PeapodsInvariant.stakingPool_stake(253063106226358333514199647342591507453153798266168220375913146771918814355,3239316176860876682422915113487822058500344893575650191064987713544339811,16083031068229554073894008156206024808099244186921884360202709001559479)
    PeapodsInvariant.aspTKN_deposit(273993910286263133516096421285094532882480892227636511286734319491693895081,26515330,3920930508472181862651158938806839046832061674102504862518328404027076182451,13)
    *wait* Time delay: 21 seconds Block delay: 1
    PeapodsInvariant.aspTKN_withdraw(492918021694239959849823204962395933559318301830995537395292228510180577503,2932,1648371,706)
        """
solidity_code = convert_to_solidity(call_sequence)
print(solidity_code)