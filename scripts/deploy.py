from brownie import CrowdFund, config, network
from web3 import Web3
from scripts.helpful_scripts import get_account, approve_token
import time


def deploy(new_deploy=False, publish=False):
    account = get_account()
    cFund = (
        CrowdFund.deploy(
            config["networks"][network.show_active()]["link_token"],
            config["networks"][network.show_active()]["keeper_registry"],
            {"from": account},
            publish_source=publish,
        )
        if new_deploy == True
        else CrowdFund[-1]
    )
    time.sleep(1)

    if new_deploy:
        print(f"cFund address {network.show_active()} ", cFund.address)
    return account, cFund


def propose(new_deploy=False, startDelay=600):
    account, cFund = deploy(new_deploy)

    approve_token(
        config["networks"][network.show_active()]["link_token"],
        cFund,
        2 * 10 ** 18,
        account,
    )
    time.sleep(2)
    startTime = int(time.time()) + startDelay
    endTime = startTime + 100
    tx = cFund.propose(
        account,
        startTime,
        endTime,
        Web3.toWei(1, "ether"),
        {"from": account},
    )
    tx.wait(1)
    campaignId = tx.events["Propose"]["_campaignId"]

    print(f"{campaignId} proposed")
    return campaignId


def fund(new_deploy=False):
    account, cFund = deploy(new_deploy)
    campaignId = propose()

    time.sleep(2)
    tx = cFund.fund(campaignId, {"from": account, "value": Web3.toWei(0.5, "ether")})
    tx.wait(1)
    amount = tx.events["Fund"]["_amount"]
    print("funded amount ", amount)
    return campaignId


def withdraw(new_deploy=False):
    account, cFund = deploy(new_deploy)
    campaignId = fund()

    tx = cFund.withdraw(campaignId, Web3.toWei(0.25, "ether"), {"from": account})
    tx.wait(1)
    amount = tx.events["Withdraw"]["_amount"]
    print("withdrawn amount ", amount)


def refund(new_deploy=False):
    account, cFund = deploy(new_deploy)
    campaignId = fund()

    time.sleep(11)
    tx = cFund.refund(campaignId, {"from": account})
    tx.wait(1)
    amount = tx.events["Refund"]["_amount"]
    print("refunded amount ", amount)


def fulfill(new_deploy=False):
    account, cFund = deploy(new_deploy)
    campaignId = fund()

    time.sleep(11)
    tx = cFund.fulfill(campaignId, {"from": account})
    tx.wait(1)
    amount = tx.events["Fulfill"]["_amount"]
    print("fulfilled amount ", amount)


def cancel(new_deploy=False):
    account, cFund = deploy(new_deploy)
    campaignId = propose(startDelay=30)

    tx = cFund.cancel(campaignId, {"from": account})
    tx.wait(1)

    print(f"Campaign {campaignId} has been cancelled")


def fund_keepers(new_deploy=False):
    account, cFund = deploy(new_deploy)
    propose()

    tx = cFund.setKeepersId(2730, {"from": account})
    tx.wait(1)
    tx = cFund.keepersFund({"from": account})
    tx.wait(1)

    linkAmount = tx.events["KeepersFund"]["_linkAmount"]
    print(f"keepers funded with {linkAmount}")


def main():
    None
