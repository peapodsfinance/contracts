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
PeapodsInvariant.leverageManager_initializePosition(7096962001175309351031708954122569597059738833862422109237148525278,1917)
    PeapodsInvariant.lendingAssetVault_donate(0,590378204232475098712366623627530365713192081665426178146478)
    PeapodsInvariant.pod_bond(0,53,0,40376823087734141632606500746807396928283596831452932060289462451179643137141)
    PeapodsInvariant.leverageManager_addLeverage(460106152462011252061248616718776899042682877647977355048945218041068417,3778112994112360068031115439735947549829468535988168576591875054435384921071,3095359457719718961078564169853718995708561395666977374049381524639)
    PeapodsInvariant.fraxPair_mint(69126886722419368835216397346996778765174464328211839883058757753226386,4017080326677565490016367644114166718794393231076032079863447007767082307800,626635908492579455494743275017931419828656934235447296989005353516858447613,621330998087583959761732745981253674161003714277593025437414475707781403260)
    PeapodsInvariant.pod_bond(1,729,0,5749399858886046861338678033104484643246859488004759738752178392496986615400)
    PeapodsInvariant.leverageManager_initializePosition(83813597819787538237266890975840318920339727174421869585582702600573140,1045)
    PeapodsInvariant.leverageManager_addLeverage(3768798417013765906626765620351696538842223677342948860509593413572536,55463650341893274962735782838387389396129693573163568715806957736773092630,2447837959499188505225838633053905473147571707163681756986408298915299579)
    *wait* Time delay: 1 seconds Block delay: 1
    PeapodsInvariant.fraxPair_redeem(34835560422674432007519860483767583651523220445179496457322932544320486794,78217852739431538933882101953667661022028545968250168924541749375642293,6717,29450193010715293154296284804587017889740150066210481111263042596776957)
    PeapodsInvariant.invariant_POD_12()
        """
solidity_code = convert_to_solidity(call_sequence)
print(solidity_code)