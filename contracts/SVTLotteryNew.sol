// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {VRFCoordinatorV2Interface} from "@chainlink/contracts@0.8.0/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts@0.8.0/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {ConfirmedOwner} from "@chainlink/contracts@0.8.0/src/v0.8/shared/access/ConfirmedOwner.sol";

contract SVTLottery is VRFConsumerBaseV2, ConfirmedOwner {

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }
    VRFCoordinatorV2Interface COORDINATOR;

    uint32 private callbackGasLimit = 100000;
    uint8 private requestConfirmations = 3;
    uint8 private numWords = 1;
    uint64 private s_subscriptionId = 181;
    bytes32 keyHash = 0x72d2b016bb5b62912afea355ebf33b91319f828738b111b723b78696b9847b63;
    address Coordinator = 0x41034678D6C633D8a95c75e1138A360a28bA15d1;

    uint8 public percentageCharge = 25;

    uint32 public totalAirdropSent = 0;
    uint32 public totalAirdrop = 100000;

    uint16 public SLTAirdropAmount = 50;

    uint256 private tenEighteen = 10**18;
    uint256 private tenEight = 10**8;
    uint256 private tenTen = 10**10;
    uint8 private hundredPercent = 100;

    uint8 private zeroValue = 0;

    bool[] private potentialToWin = [
        false, false, false, false, false, false, false, true, false, false, false, false, false, false, false
    ];
    uint256 private prizeMultipler = 10;

    address public SLTAddress = 0x42B5bcE9095aeC6E605991cA6dE23330C43b124D;

    address[] public contributors;

    mapping (address => bool) private addressAccessLocked;

    mapping (uint256 => RequestStatus) public s_requests;

    mapping (address => bool) private addressToParticipationStatus;

    mapping (address => bool) public addressToAidropClaimed;

    mapping (address => uint256) public addressToRequestId;
    
    mapping (address => uint256) public addressToAmountContributed;
    mapping (address => uint256) public addressToTotalFundsAtTimeOfContribution;

    mapping (address => uint256) private addressToLotteryStake;

    IERC20 private SLT = IERC20(SLTAddress);

    modifier nonReentrant() {
        require(!addressAccessLocked[msg.sender], "Reentrancy guard: locked");
        addressAccessLocked[msg.sender] = true;
        _;
        addressAccessLocked[msg.sender] = false;
    }

    modifier transferAllowedSLT(uint256 _amount) {
        require(SLT.allowance(msg.sender, address(this)) >= _amount, "Insufficient SLT allowance");
        _;
    }

    modifier totalAirdropSentCheck() {
        require(totalAirdropSent < totalAirdrop, "Airdrop Not Available Currently");
        _;
        totalAirdropSent += SLTAirdropAmount;
    }

    modifier withdrawalPossible() {
        require(SLT.balanceOf(address(this)) > addressToTotalFundsAtTimeOfContribution[msg.sender], "You are not eligible to withdraw");
        _;
    }

    modifier airdropClaimed() {
        require(!addressToAidropClaimed[msg.sender], "You have already claimed an airdrop");
        _;
        addressToAidropClaimed[msg.sender] = true;
    }

    modifier contributorExists() {
        require(addressToAmountContributed[msg.sender] > zeroValue, "Contributor currently does not have any funds within the contract");
        _;
    }

    modifier addressSLTBalanceCheck(uint256 _amountRequired) {
        require(SLT.balanceOf(address(this)) >= _amountRequired, "Not enough SLT in contract to enable this draw");
        _;
    }

    modifier contributorDoesNotExist() {
        require(addressToAmountContributed[msg.sender] == zeroValue, "Contributor already exists");
        _;
    }

    modifier participationCheck() {
        require(addressToParticipationStatus[msg.sender] == true, "Not a participant. Choose a draw");
        _;
        addressToParticipationStatus[msg.sender] == false;
    }

    modifier randomNumberAvailable() {
        uint256 _requestId = addressToRequestId[msg.sender];
        require(s_requests[_requestId].fulfilled == true, "Random Number not yet Generated");
        _;
    }

    constructor()
    ConfirmedOwner(msg.sender)
    VRFConsumerBaseV2(Coordinator) 
    {
        COORDINATOR = VRFCoordinatorV2Interface(
            Coordinator
        );
    }

    function contribute(uint256 _SLTTokenAmount)
        external 
        nonReentrant
        contributorDoesNotExist
        transferAllowedSLT(_SLTTokenAmount)
    {
        SLT.transferFrom(msg.sender, address(this), _SLTTokenAmount);
        addressToTotalFundsAtTimeOfContribution[msg.sender] = SLT.balanceOf(address(this)) - _SLTTokenAmount;
        addressToAmountContributed[msg.sender] = _SLTTokenAmount;
        contributors.push(msg.sender);
    }

    function getWithdrawalAmount()
        public
        view
        contributorExists
        withdrawalPossible
        returns(uint256 contributionSLTTokenAmountAfterCharge, uint256 indexOfContributor)
    {
        uint256 totalFunds = SLT.balanceOf(address(this));
        uint256 contributorWeight;
        uint256 currentContributorWeight;
        uint256 amountContributed;
        uint256 contributorAmount;
        uint256 totalFundsAtTimeOfContribution;
        uint256 totalWeight = 0;
        uint256 amountToWithdraw;
        uint256 contributionCharge;
        for(uint256 index = 0; index < contributors.length; index++) {
            amountContributed = addressToAmountContributed[contributors[index]];
            totalFundsAtTimeOfContribution = addressToTotalFundsAtTimeOfContribution[contributors[index]];
            currentContributorWeight = amountContributed * (totalFunds - totalFundsAtTimeOfContribution);
            totalWeight += currentContributorWeight;
            if(msg.sender == contributors[index]) {
                contributorWeight = currentContributorWeight;
                contributorAmount = amountContributed;
                indexOfContributor = index;
            }
        }
        amountToWithdraw = (((contributorWeight * tenEight) / totalWeight) * totalFunds) / tenEight;
        if(amountToWithdraw > contributorAmount){
            contributionCharge = (percentageCharge * (amountToWithdraw - contributorAmount)) / hundredPercent;
        }
        else{
            contributionCharge = 0;
        }
        contributionSLTTokenAmountAfterCharge = amountToWithdraw - contributionCharge;
        return (contributionSLTTokenAmountAfterCharge, indexOfContributor);
    }

    function withdrawContribution()
        external
        nonReentrant
    {
        (uint256 contributionSLTTokenAmountAfterCharge, uint256 indexOfContributor) = getWithdrawalAmount();
        if(contributionSLTTokenAmountAfterCharge > 0) {
            contributors[indexOfContributor] = contributors[contributors.length - 1];
            contributors.pop();
            addressToAmountContributed[msg.sender] = zeroValue;
            addressToTotalFundsAtTimeOfContribution[msg.sender] = zeroValue;
        }
        SLT.transfer(msg.sender, contributionSLTTokenAmountAfterCharge);
    }

    function updatePercentage(uint8 _percentage)
        external 
        onlyOwner
    {
        percentageCharge = _percentage;
    }

    function playLottery(uint256 _sltAmountToStake)
        external
        addressSLTBalanceCheck(_sltAmountToStake * 10)
        transferAllowedSLT(_sltAmountToStake)
    {
        SLT.transferFrom(msg.sender, address(this), _sltAmountToStake);
        addressToParticipationStatus[msg.sender] = true;
        addressToRequestId[msg.sender] = requestRandomWords();
        addressToLotteryStake[msg.sender] = _sltAmountToStake;
    }

    function requestRandomWords()
        internal
        returns (uint256 requestId)
    {
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        return requestId;
    }

    function fulfillRandomWords( uint256 _requestId, uint256[] memory _randomWords)
        internal
        override
    {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
    }

    function getFinalResultValue()
        public
        view
        participationCheck
        randomNumberAvailable
        returns(uint256 SLTAmountWon)
    {
        uint256 requestId = addressToRequestId[msg.sender];
        uint256 realRandomNumber = getRandomNumber(requestId);
        uint256 SLTAmountToSend = zeroValue;
        uint256 stakeAmount = addressToLotteryStake[msg.sender];
        uint256 randomNumber = realRandomNumber % potentialToWin.length;
        bool status = potentialToWin[randomNumber];
        if(status == false){
            SLTAmountToSend = 0;
        }else{
            SLTAmountToSend = stakeAmount * prizeMultipler;
        }
        return SLTAmountToSend;
    }

    function getFinalResult()
        public
    {
        uint256 SLTAmountToSend = getFinalResultValue();
        require(SLTAmountToSend > 0, "You did not win. Better luck next time!");
        SLT.transfer(msg.sender, SLTAmountToSend);
        addressToLotteryStake[msg.sender] = zeroValue;
    }

    function getRandomNumber(uint256 _requestId)
        public
        view
        returns(uint256)
    {
        RequestStatus memory request = s_requests[_requestId];
        return (request.randomWords[0]);
    }

    function claimAirdropSLT()
        external
        airdropClaimed
        totalAirdropSentCheck
    {
        SLT.transfer(msg.sender, SLTAirdropAmount * tenEighteen);
    }
    
    function updateSLTAirdropLimit(uint16 _SLTAirdropLimit)
        external
        onlyOwner
    {
        totalAirdrop = _SLTAirdropLimit;
    }

    function updateSLTAirdropAmount(uint16 _newTokenAmount)
        external
        onlyOwner
    {
        SLTAirdropAmount = _newTokenAmount;
    }
    
    function updatePrizeMultipler(uint16 _prizeMultipler)
        external
        onlyOwner
    {
        prizeMultipler = _prizeMultipler;
    }
}