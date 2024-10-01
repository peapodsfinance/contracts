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
PeapodsInvariant.leverageManager_initializePosition(3135109201343607296164605610919085127145970708021829018762070770643778,418057)
    PeapodsInvariant.lendingAssetVault_donate(23,31229953627649088530616146548222765510572631369500739503739659518345843599)
    PeapodsInvariant.pod_bond(0,3127589,1710,40376823087734141632606500746807396928283596831452932060289462451179643137141)
    PeapodsInvariant.leverageManager_addLeverage(6456357403818909750492472862404977683237738105723823504769352855941609776133,18896218056052526071403679464359509907904387201962767474231895294398192098868,16140772492581006197302117417653279683323316390703263948864000516848942566)
    *wait* Time delay: 21 seconds Block delay: 1
    PeapodsInvariant.leverageManager_addLeverage(4890656399217044410169330225154913468551492993126690263377236427780444287759,115792089237316195423570985008687907853269984665640564039457584007913129639932,267578008525601788823735652918594924471536198387548725188114397516617366)
    PeapodsInvariant.fraxPair_removeCollateral(4577761802947594192370505727603543103557686895229952921286002659453146092313,1127942347432105304419924948824898178948346121650232326555630539015791,1653048,6)
    PeapodsInvariant.leverageManager_removeLeverage(3188455,69695,115792089237316195423570985008687907853269984665640564039457584007913129639932,635784833585941579056494292440928635078572722868771404868778327515094091925)
    PeapodsInvariant.leverageManager_addLeverage(104450926436516555664020780774308065618424010404594549054367916210464057088329,115792089237316195423570985008687907853269984665640564039457584007913129639932,0)
    PeapodsInvariant.lendingAssetVault_deposit(52793294824471845802958790501310927466992969714900288610816000939,0,3119285228086136608357535659702469447500741731487866507277253) Time delay: 4 seconds Block delay: 1
    *wait* Time delay: 1 seconds Block delay: 1
    PeapodsInvariant.fraxPair_liquidate(15048674466093684075397741811301565930270060099424712363854427437447965727,275419969782750717868681581)
        """
solidity_code = convert_to_solidity(call_sequence)
print(solidity_code)