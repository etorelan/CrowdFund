//SPDX-License-Identifier: MIT
/// @title CrowdFund
/// @author etorelan
/// @notice Smart contract enabling to pool money for a specified reciever address during a specific time and
/// @notice have that money sent to the reciever thanks to chainlink keepers running every 24 hours

pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperRegistryInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ILinkToken.sol";

contract CrowdFund is KeeperCompatibleInterface, Ownable {
    KeeperRegistryInterface keeperRegistry;
    ILinkToken linkToken;
    uint256 campaignId;
    uint256 immutable interval = 24 hours;
    uint256 lastTimeStamp;
    uint256 linkFee;
    uint256 keepersId;

    mapping(uint256 => Campaign) campaigns;
    mapping(address => mapping(uint256 => uint256)) amountFunded;

    constructor(address _linkToken, address _keeperRegistry) {
        lastTimeStamp = block.timestamp;
        campaignId = 1;
        linkFee = 2 * 10**18;
        linkToken = ILinkToken(_linkToken);
        keeperRegistry = KeeperRegistryInterface(_keeperRegistry);
    }

    modifier isOngoing(uint256 _campaignId) {
        require(
            (block.timestamp > campaigns[_campaignId]._startTime) &&
                (block.timestamp < campaigns[_campaignId]._endTime),
            "Campaign is not ongoing"
        );
        require(
            campaigns[_campaignId]._proposed == true,
            "Campaign is not ongoing"
        );
        _;
    }

    event Propose(
        address _initiator,
        address _receiver,
        uint256 _campaignId,
        uint32 _startTime,
        uint32 _endTime
    );

    event Fund(address _funder, uint256 _campaignId, uint256 _amount);

    event Withdraw(address _withdrawer, uint256 _campaignId, uint256 _amount);

    event Cancel(uint256 _campaignId);

    event Fulfill(address _receiver, uint256 _campaignId, uint256 _amount);

    event Refund(address _refunder, uint256 _campaignId, uint256 _amount);

    event KeepersFund(uint256 _linkAmount);

    struct Campaign {
        address _initiator;
        address _receiver;
        uint32 _startTime;
        uint32 _endTime;
        uint256 _amountFunded;
        uint256 _goal;
        bool _proposed;
    }

    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory)
    {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }

    function performUpkeep(bytes calldata) external override {
        if ((block.timestamp - lastTimeStamp) > interval) {
            for (uint256 i = 1; i < campaignId; i++) {
                if (
                    campaigns[i]._startTime > 0 &&
                    campaigns[i]._endTime <= block.timestamp
                ) {
                    fulfill(i);
                }
            }
            lastTimeStamp = block.timestamp;
            keepersFund();
        }
    }

    function propose(
        address _receiver,
        uint32 _startTime,
        uint32 _endTime,
        uint256 _goal
    ) public payable {
        require(
            linkToken.transferFrom(msg.sender, address(this), linkFee),
            "Link token transfer failed"
        );
        require(
            _startTime < _endTime,
            "_startTime cannot be higher than _endTime."
        );
        require(
            _endTime - _startTime <= 30 days,
            "Campaign duration cannot be longer than 30 days"
        );
        require(
            _endTime - _startTime >= 12 hours,
            "Campaign cannot end sooner than after 12 hours"
        );
        require(
            _startTime >= block.timestamp,
            "Campaign cannot start sooner than block.timestamp"
        );
        require(_goal >= 0.01 ether, "Goal is not high enough");

        campaigns[campaignId] = Campaign({
            _initiator: msg.sender,
            _receiver: _receiver,
            _startTime: _startTime,
            _endTime: _endTime,
            _amountFunded: 0,
            _goal: _goal,
            _proposed: true
        });

        emit Propose(msg.sender, _receiver, campaignId, _startTime, _endTime);

        campaignId += 1;
    }

    function fund(uint32 _campaignId) external payable isOngoing(_campaignId) {
        require(_campaignId < campaignId, "Specified ID doesn't exist");
        Campaign storage campaign = campaigns[_campaignId];
        campaign._amountFunded += msg.value;
        amountFunded[msg.sender][_campaignId] += msg.value;

        emit Fund(msg.sender, _campaignId, msg.value);
    }

    function withdraw(uint32 _campaignId, uint256 _amount)
        external
        isOngoing(_campaignId)
    {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            _amount <= amountFunded[msg.sender][_campaignId],
            "Specified amount is higher than available amount"
        );

        campaign._amountFunded -= _amount;
        amountFunded[msg.sender][_campaignId] -= _amount;
        payable(msg.sender).transfer(_amount);

        emit Withdraw(msg.sender, _campaignId, _amount);
    }

    function cancel(uint256 _campaignId) external {
        Campaign storage campaign = campaigns[_campaignId];
        require(
            msg.sender == campaign._initiator,
            "msg.sender is not the initiator"
        );
        require(
            block.timestamp < campaign._startTime,
            "Campaign can only be cancelled before the start"
        );

        delete campaigns[_campaignId];

        emit Cancel(_campaignId);
    }

    function fulfill(uint256 _campaignId) public {
        Campaign storage campaign = campaigns[_campaignId];
        require(block.timestamp > campaign._endTime, "Campaign is not ended");

        uint256 amountToSend = campaign._amountFunded;
        campaign._amountFunded = 0;
        payable(campaign._receiver).transfer(amountToSend);

        delete campaigns[_campaignId];

        emit Fulfill(msg.sender, _campaignId, amountToSend);
    }

    function refund(uint256 _campaignId) external {
        Campaign storage campaign = campaigns[_campaignId];
        require(block.timestamp > campaign._endTime, "Campaign is not ended");
        require(
            campaigns[_campaignId]._proposed == true,
            "Campaign has been fulfilled"
        );
        require(
            amountFunded[msg.sender][_campaignId] > 0,
            "Refund unavailable due to no amount funded"
        );
        require(
            campaign._amountFunded < campaign._goal,
            "Goal has been achieved, refund is unavailable"
        );

        uint256 amountToSend = amountFunded[msg.sender][_campaignId];
        amountFunded[msg.sender][_campaignId] = 0;
        campaign._amountFunded -= amountToSend;
        payable(msg.sender).transfer(amountToSend);

        emit Refund(msg.sender, _campaignId, amountToSend);
    }

    function keepersFund() public {
        linkToken.approve(
            address(keeperRegistry),
            linkToken.balanceOf(address(this))
        );
        keeperRegistry.addFunds(
            keepersId,
            uint96(linkToken.balanceOf(address(this)))
        );
        emit KeepersFund(linkFee);
    }

    function setKeepersId(uint256 _id) external onlyOwner {
        keepersId = _id;
    }

    function getCampaign(uint256 _campaignId)
        public
        view
        returns (Campaign memory)
    {
        require(_campaignId < campaignId, "Specified ID doesn't exist");
        return campaigns[_campaignId];
    }
}
