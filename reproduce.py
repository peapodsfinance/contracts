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
PeapodsInvariant.pod_bond(31419840641731213979508341201566637012967524853285302739084770870420106598,375081572315913502715820902685145867855482442794160313223960026690988983,9892271962237880886842229474321039178359663870992092511606712412117662,271623788221548225522252530504199281646827715203697126735444684942580653467)
    PeapodsInvariant.leverageManager_initializePosition(0,2873623313533063030948900659238916511641729233133322317226817931)
    PeapodsInvariant.leverageManager_initializePosition(91796868250787052244396204180337100482304576248536470825334,3)
    PeapodsInvariant.pod_bond(182529254693297869548808555355491718575929602899650119333467603926164313,19019988268679194606683024775213836478706299939077452246905151817058611735,0,195142413648582603965278722008899869974060046834873831284646952907412388109)
    PeapodsInvariant.leverageManager_addLeverage(2,3362799561380903562609695444898889467561956522706184499879484881442,1634677004341145404881435488373664130757427624717990512)
    PeapodsInvariant.lendingAssetVault_mint(0,247733550008027434711486187166829,4213070482535221240233548230995170674017)
    PeapodsInvariant.leverageManager_addLeverage(1,104826939601904124205059194484919242813156233815199892779696157880015872,0)
    PeapodsInvariant.lendingAssetVault_redeemFromVault(3098,137121979934319182734850280165263761524316928750487259520389661331673550463,0)
        """
solidity_code = convert_to_solidity(call_sequence)
print(solidity_code)