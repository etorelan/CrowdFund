import pytest, time
from brownie import CrowdFund, config, accounts, network
from web3 import Web3
from scripts.helpful_scripts import get_account, approve_token


"""""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""
Tests in the integration directory are run with the 76. line of contracts/CrowdFund.sol commented out 

76. require( _endTime - _startTime >= 12 hours, "Campaign cannot end sooner than after 12 hours");
""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """""" """"""


@pytest.mark.parametrize("refund", [True, False])
def test_integration(refund):
    account = get_account()
    cFund = CrowdFund.deploy(
        config["networks"][network.show_active()]["link_token"],
        2 * 10 ** 18,
        {"from": account},
        publish_source=config["networks"][network.show_active()]["verify"],
    )
    time.sleep(1)
    print(f"cFund address {network.show_active()} ", cFund.address)

    time.sleep(2)
    startTime = int(time.time()) + 1
    endTime = startTime + 10
    tx = cFund.propose(
        account,
        startTime,
        endTime,
        Web3.toWei(1, "ether"),
        {"from": account},
    )
    tx.wait(1)
    campaignId = tx.events["Propose"]["_campaignId"]

    time.sleep(2)
    tx = cFund.fund(campaignId, {"from": account, "value": Web3.toWei(0.5, "ether")})
    tx.wait(1)
    amount = tx.events["Fund"]["_amount"]
    print("funded amount ", amount)
    assert amount == Web3.toWei(0.5, "ether")

    tx = cFund.withdraw(campaignId, Web3.toWei(0.25, "ether"), {"from": account})
    tx.wait(1)
    amount = tx.events["Withdraw"]["_amount"]
    print("withdrawn amount ", amount)
    assert amount == Web3.toWei(0.25, "ether")

    if refund:
        time.sleep(11)
        tx = cFund.refund(campaignId, {"from": account})
        tx.wait(1)
        amount = tx.events["Refund"]["_amount"]
        print("refunded amount ", amount)
        assert amount == Web3.toWei(0.25, "ether")
    else:
        time.sleep(11)
        tx = cFund.fulfill(campaignId, {"from": account})
        tx.wait(1)
        amount = tx.events["Fulfill"]["_amount"]
        print("fulfilled amount ", amount)
        assert amount == Web3.toWei(0.25, "ether")
