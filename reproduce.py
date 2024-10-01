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
PeapodsInvariant.leverageManager_initializePosition(3170994360843214229791361598937171867352410844517961335338722642050982481790,2847101)
    PeapodsInvariant.lendingAssetVault_donate(599,92393461251032154622739909774334826957153098844209239018556631232040888350)
    PeapodsInvariant.pod_bond(30,3127589,69625,40376823087734141632606500746807396928283596831452932060289462451179643137141)
    PeapodsInvariant.leverageManager_addLeverage(6456357403818909750492472862404977683237738105723823504769352855941609776133,18896218056052526071403679464359509907904387201962767474231895294398192098868,39591106487985563893078065606701835112383209820265903330616755470568388614)
    PeapodsInvariant.fraxPair_redeem(2,148535164871777002579919131688934403148530423126301050038,11903718798588460192823683427264819786864488953660580627361319045545,0) Time delay: 24 seconds Block delay: 9
    PeapodsInvariant.leverageManager_addLeverage(4890656399217044410169330225154913468551492993126690263377236427780444287759,115792089237316195423570985008687907853269984665640564039457584007913129639932,656244559344663472843835220100327736309874961680352937820337689470919021582)
    PeapodsInvariant.fraxPair_removeCollateral(10998460059801780514734410362290562161745544430430979134525165188931652922505,259452895111266467637580386590025850726338355939178113513197643627579831,8652381,106628)
    PeapodsInvariant.leverageManager_removeLeverage(335613387,4317116,115792089237316195423570985008687907853269984665640564039457584007913129639932,1162033533043106291066545300594863555087523196872249741329694402241817469549)
    PeapodsInvariant.leverageManager_addLeverage(104450926436516555664020780774308065618424010404594549054367916210464057088329,115792089237316195423570985008687907853269984665640564039457584007913129639932,30)
    PeapodsInvariant.lendingAssetVault_deposit(5034295896465173239606185870701555452688224854964033569616892171357853,0,2910746797760178418536728868126027328665109085009980907231197737084) Time delay: 185 seconds Block delay: 30
    *wait* Time delay: 1 seconds Block delay: 71
    PeapodsInvariant.fraxPair_liquidate(514605345466824601913749312262515245449344620754573878265793591125753732143,196150735647263214969937456777560)
        """
solidity_code = convert_to_solidity(call_sequence)
print(solidity_code)