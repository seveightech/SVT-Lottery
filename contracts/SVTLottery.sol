// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ConfirmedOwner} from "@chainlink/contracts@0.8.0/src/v0.8/shared/access/ConfirmedOwner.sol";
import {VRFV2WrapperConsumerBase} from "@chainlink/contracts@0.8.0/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import {LinkTokenInterface} from "@chainlink/contracts@0.8.0/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract SVTLottery is VRFV2WrapperConsumerBase, ConfirmedOwner {

    struct RequestStatus {
        uint256 paid;
        bool fulfilled;
        uint256[] randomWords;
    }

    uint32 private callbackGasLimit = 100000;
    uint8 private requestConfirmations = 3;
    uint8 private numWords = 1;

    uint8 public percentageCharge = 25;

    uint32 public totalAirdropSent = 0;
    uint32 public totalAirdrop = 100000;

    uint16 public SLTAirdropAmount = 50;

    uint256 private tenEighteen = 10**18;
    uint256 private tenEight = 10**8;
    uint256 private tenTen = 10**10;
    uint8 private hundredPercent = 100;

    uint8 private zeroValue = 0;
    uint private getWithdrawalAmountPaidvalue = 0;
    uint private getFinalResultValuePaidvalue = 0;

    bool[] private potentialToWin = [
        false, false, false, false, false, false, false, true, false, false, false, false, false, false, false
    ];
    uint256 private prizeMultipler = 10;

    address public SLTAddress = 0x42B5bcE9095aeC6E605991cA6dE23330C43b124D;

    address linkAddress = 0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;

    address wrapperAddress = 0x2D159AE3bFf04a10A355B608D22BDEC092e934fa;

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

    event FinalResult(uint256 SLTAmountWon);
    event Withdrawal(uint256 SLTAmountAvailable);
    event Contribution(uint256 SLTAmountContributed);
    event PlayLottery(uint256 SLTAmountStakedInLottery);
    event Airdrop(uint256 SLTAirdropAmount);
    event NewPrizeMultipler(uint256 prizeMultipler);
    event NewAirdropAmount(uint256 airdropAmount);
    event NewAirdropLimit(uint256 airdropLimit);
    event NewWithdrawalPercentage(uint256 withdrawalPercentage);

    constructor()
        ConfirmedOwner(msg.sender)
        VRFV2WrapperConsumerBase(linkAddress, wrapperAddress)
    {}

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
        emit Contribution(_SLTTokenAmount);
    }

    function getWithdrawalAmount()
        public
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
        emit Withdrawal(contributionSLTTokenAmountAfterCharge);
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
        emit NewWithdrawalPercentage(_percentage);
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
        emit PlayLottery(_sltAmountToStake);
    }

    function requestRandomWords()
        internal
        returns (uint256 requestId)
    {
        requestId = requestRandomness(
            callbackGasLimit,
            requestConfirmations,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomWords: new uint256[](0),
            fulfilled: false
        });
        return requestId;
    }

    function fulfillRandomWords( uint256 _requestId, uint256[] memory _randomWords)
        internal
        override
    {
        require(s_requests[_requestId].paid > 0, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
    }

    function getFinalResultValue()
        public
        participationCheck
        randomNumberAvailable
        returns(uint256 SLTAmountWon)
    {
        uint256 requestId = addressToRequestId[msg.sender];
        uint256 realRandomNumber = getRandomNumber(requestId);
        uint256 stakeAmount = addressToLotteryStake[msg.sender];
        uint256 randomNumber = realRandomNumber % potentialToWin.length;
        bool status = potentialToWin[randomNumber];
        if(status == false){
            SLTAmountWon = 0;
        }else{
            SLTAmountWon = stakeAmount * prizeMultipler;
        }
        emit FinalResult(SLTAmountWon);
        return SLTAmountWon;
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
        emit Airdrop(SLTAirdropAmount);
    }
    
    function updateSLTAirdropLimit(uint16 _SLTAirdropLimit)
        external
        onlyOwner
    {
        totalAirdrop = _SLTAirdropLimit;
        emit NewAirdropLimit(_SLTAirdropLimit);
    }

    function updateSLTAirdropAmount(uint16 _newTokenAmount)
        external
        onlyOwner
    {
        SLTAirdropAmount = _newTokenAmount;
        emit NewAirdropAmount(_newTokenAmount);
    }
    
    function updatePrizeMultipler(uint16 _prizeMultipler)
        external
        onlyOwner
    {
        prizeMultipler = _prizeMultipler;
        emit NewPrizeMultipler(_prizeMultipler);
    }

    function withdrawLink() 
    public 
    onlyOwner 
    {
        LinkTokenInterface link = LinkTokenInterface(linkAddress);
        require(
            link.transfer(msg.sender, link.balanceOf(address(this))),
            "Unable to transfer"
        );
    }
}