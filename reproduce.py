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
PeapodsInvariant.pod_bond(288567818787326643023506815421089704617048639194509319202485712218260114617,29515901080938621889877141707036352226864468261646330083102350409534879807,28256599680508433858763901613522706652795966666826605659660450702110,3751223273476981504383446139001619864832943303305560785665809932553786858138)
    PeapodsInvariant.leverageManager_initializePosition(2,864785375698752058026248862771397146954785887553859643720868042307)
    PeapodsInvariant.leverageManager_initializePosition(5595072295542652736919814920051382776810433011150861666666484,3)
    PeapodsInvariant.pod_bond(1058043035031271676877037547360272025750726995625444698139083556944597505,37099228305815352059887914428010197444677666189399271658359950942529764283,0,143506537564179499103755282911983298564367649682125205205130895513828436923)
    PeapodsInvariant.leverageManager_addLeverage(5,41706035278414378014825701564606898084637215157942598606193520988966,102073968472749201022494914351009447513568879680598929536)
    PeapodsInvariant.lendingAssetVault_mint(0,637742026157715443619636869731791345096885118,313986741269926707370551517818097301939177071860)
    PeapodsInvariant.leverageManager_addLeverage(1,1294187552646389794390633050136096068607040314971578608717635250460852493,0)
    PeapodsInvariant.targetSenders() Time delay: 89 seconds Block delay: 71
    PeapodsInvariant.lendingAssetVault_mint(841691,112193634547402445825324080083248207536574920660550846273564449088938344816,126366872935807815185412166746919557930666910384714995734994666647051581568)
        """
solidity_code = convert_to_solidity(call_sequence)
print(solidity_code)