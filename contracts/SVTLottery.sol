// SPDX-License-Identifier: MIT

pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFV2WrapperConsumerBase.sol";
import "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";

contract SVTLottery is VRFV2WrapperConsumerBase, ConfirmedOwner {

    // Struct for storing generated random number
    struct RequestStatus {
        uint256 paid;
        bool fulfilled;
        uint256[] randomWords;
    }

    // Variables for generating random number
    uint32 private callbackGasLimit = 100000;
    uint8 private requestConfirmations = 3;
    uint8 private numWords = 1;

    // Percentage to be charged upon withdrawal of contribution
    uint8 public percentageCharge = 5;

    // Airdrop Threshhold
    uint32 public totalAirdropSent = 0;
    uint32 public totalAirdrop = 2500;

    // Reward Token variables
    uint16 public SLTRewardAmountSeven = 10;
    uint16 public SLTRewardAmountSeventy = 25;
    uint16 public SLTRewardAmountSevenHundred = 250;
    uint16 public SLTRedemptionFee = 5;
    uint16 public SLTAirdropAmount = 50;
    uint16 public SLTPricePerRedemption = 1;

    // Conversion Prices
    uint256 private tenEighteen = 10**18;
    uint256 private tenEight = 10**8;
    uint256 private tenTen = 10**10;
    uint8 private hundredPercent = 100;

    // Prices for each category
    uint16 public entryPriceForWorthSeven = 4;
    uint16 public entryPriceForWorthSeventy = 7;
    uint16 public entryPriceForWorthSevenHundred = 20;

    // Potential Prize Amounts
    uint16 public WorthSevenPotential = 7;
    uint16 public WorthSeventyPotential = 70;
    uint16 public WorthSevenHundredPotential = 700;

    // Zero Value
    uint8 private zeroValue = 0;

    // Arrays for prizes
    uint256[] private worthSeven = [
        1, 1, 3, 1, 2, 1, 1, 7, 1, 4
    ];
    uint256[] private worthSeventy = [
        1, 2, 3, 1, 2, 3, 3, 1, 1, 1, 1, 2, 3, 1, 4, 2, 2, 3, 1, 6, 1, 70, 1, 1, 1, 2, 3, 1, 2, 3
    ];
    uint256[] private worthSevenHundred = [
        1, 1, 12, 1, 2, 3, 10, 7, 3, 4, 2, 1, 1, 11, 1, 1, 2, 3, 5, 2, 15, 1, 1, 5, 4, 2, 1, 1, 1, 7, 7, 1, 1, 1, 1, 1, 700, 1, 1, 12
    ];

    // address for airdrop tokens
    address public SLTAddress;

    // address WRAPPER - hardcoded for Sepolia
    address private wrapperAddress = 0xab18414CD93297B0d12ac29E63Ca20f515b3DB46; // 0x5A861794B927983406fCE1D062e00b9368d97Df6

    // Link Token Address - hardcoded for Sepolia
    address private linkTokenAddress = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // 0x514910771AF9Ca656af840dff83E8264EcF986CA

    //address public priceFeedMainnet = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;
    address private priceFeedSepolia = 0xc59E3633BAAC79493d908e63626716e204A45EdF;

    // Contributors List
    address[] public contributors;

    // Mapping for reentrancy guard to prevent recursive calls
    mapping (address => bool) private addressAccessLocked;

    // Mapping for Request ID to Random Number Stuct
    mapping (uint256 => RequestStatus) public s_requests;

    // Mapping for Address to Participation Status
    mapping (address => bool) private addressToParticipationStatus;

    // Mapping for Address to Airdrop claimed
    mapping (address => bool) public addressToAidropClaimed;

    // Mapping for address to Request ID
    mapping (address => uint256) public addressToRequestId;
    
    // Mapping to store the amount contributed by each address
    mapping (address => uint256) public addressToAmountContributed;
    mapping (address => uint256) public addressToTotalFundsAtTimeOfContribution;

    // Mapping for Address to Ability to participate
    mapping (address => uint256) private addressToDraw;

    // Chainlink price feed interface
    AggregatorV3Interface private priceFeed = AggregatorV3Interface(priceFeedSepolia);

    // Link token interface
    LinkTokenInterface private link = LinkTokenInterface(linkTokenAddress);

    // Reward token interface
    IERC20 private SLT;

    // Events to log various activities on the smart contract
    event Contribution(address indexed contributor, uint256 linkTokenAmount, uint256 totalContributions, string reason);
    event StatusUpdate(address indexed participant, uint256 Amount, string reason);
    event LinkTokensReceived(address indexed sender, uint256 linkTokenAmount, uint256 totalLinkTokensInContract, string reason);

    // Modifier: Prevents reentrancy attacks
    modifier nonReentrant() {
        require(!addressAccessLocked[msg.sender], "Reentrancy guard: locked");
        addressAccessLocked[msg.sender] = true;
        _;
        addressAccessLocked[msg.sender] = false;
    }

    // Modifier: Require entry amount to be equal to or greater than entry price
    modifier addressLinkBalanceCheck(uint256 _amountRequired) {
        require(link.balanceOf(address(this)) >= _amountRequired, "Not enough Link in contract to enable this draw");
        _;
    }

    // Modifier: Require sender to have allowed contract to be able to spend Link tokens
    modifier transferAllowedLink(uint256 _amount) {
        require(link.allowance(msg.sender, address(this)) >= _amount, "Insufficient Link allowance");
        _;
    }

    // Modifier: Require sender to have allowed contract to be able to spend Link tokens
    modifier transferAllowedSLT(uint256 _amount) {
        require(SLT.allowance(msg.sender, address(this)) >= _amount, "Insufficient SLT allowance");
        _;
    }

    // Modifier: Require sender to have allowed contract to be able to spend Link tokens
    modifier totalAirdropSentCheck() {
        require(totalAirdropSent < totalAirdrop, "Airdrop Not Available Currently");
        _;
        totalAirdropSent += SLTAirdropAmount;
    }

    // Modifier: Check if withdrawal is possible
    modifier withdrawalPossible() {
        require(link.balanceOf(address(this)) > addressToTotalFundsAtTimeOfContribution[msg.sender], "You are not eligible to withdraw");
        _;
    }

    // Modifier: Check if withdrawal is possible
    modifier airdropClaimed() {
        require(!addressToAidropClaimed[msg.sender], "You have already claimed an airdrop");
        _;
        addressToAidropClaimed[msg.sender] = true;
    }

    // Modifier: Require sender to have more than the required redemption amount of SLT tokens
    modifier verifySLTRedemptionAmount() {
        require(SLT.balanceOf(msg.sender) >= SLTRedemptionFee, "Insufficient SLT balance");
        _;
    }

    // Modifier: Requires the contributor to exist (have contributed ETH)
    modifier contributorExists() {
        require(addressToAmountContributed[msg.sender] > zeroValue, "Contributor currently does not have any funds within the contract");
        _;
    }

    // Modifier: Requires the contributor to not exist
    modifier contributorDoesNotExist() {
        require(addressToAmountContributed[msg.sender] == zeroValue, "Contributor already exists");
        _;
    }

    // Modifier: Range check for contributors list index
    modifier participationCheck() {
        require(addressToParticipationStatus[msg.sender] == true, "Not a participant. Choose a draw");
        _;
        addressToParticipationStatus[msg.sender] == false;
    }

    // Modifier: Require random number to be available
    modifier randomNumberAvailable() {
        uint256 _requestId = addressToRequestId[msg.sender];
        require(s_requests[_requestId].fulfilled == true, "Random Number not yet Generated");
        _;
    }

    // Modifier: Check amount of Link tokens in contract
    modifier linkAmountCheck() {
        require(link.balanceOf(address(this)) > zeroValue, "Not enough Link tokens in contract");
        _;
    }

    // Modifier: Check amount of SLT tokens in contract
    modifier SLTAmountCheck() {
        require(SLT.balanceOf(address(this)) > zeroValue, "Not enough SLT tokens in contract");
        _;
    }

    constructor()
    ConfirmedOwner(msg.sender)
    VRFV2WrapperConsumerBase(linkTokenAddress, wrapperAddress) 
    {}

    // Function: Get the current ETH price from the Chainlink price feed
    function checkLinkPrice()
        internal
        view
        returns(uint256)
    {
        (,int256 price,,,) = priceFeed.latestRoundData();
        uint256 LinkPrice = uint256(price) * tenTen;
        return LinkPrice;
    }

    // Function: Convert ETH to dollar equivalent
    // function convertLinkToDollar(uint256 _LinkAmountInWei)
    //     internal 
    //     view 
    //     returns(uint256)
    // {
    //     uint256 currentEthPrice = checkLinkPrice();
    //     uint256 dollarEquivalent = (_LinkAmountInWei * currentEthPrice) / tenEighteen;
    //     return dollarEquivalent;
    // }

    // Function: Convert dollar to ETH equivalent
    function convertDollarToLink(uint256 dollarAmount)
        internal
        view
        returns(uint256) 
    {
        uint256 currentLinkPrice = checkLinkPrice();
        uint256 LinkEquivalent = ((dollarAmount * tenEighteen) / (currentLinkPrice / tenTen)) * tenEight;
        return LinkEquivalent;
    }

    // Function: Allow contributors to contribute ETH to the smart contract
        function contribute(uint256 _linkTokenAmount)
        external 
        nonReentrant
        contributorDoesNotExist
        transferAllowedLink(_linkTokenAmount)
    {
        address senderAddress = msg.sender;
        link.transferFrom(msg.sender, address(this), _linkTokenAmount);
        addressToTotalFundsAtTimeOfContribution[senderAddress] = link.balanceOf(address(this)) - _linkTokenAmount;
        addressToAmountContributed[senderAddress] = _linkTokenAmount;
        contributors.push(senderAddress);
        emit Contribution(senderAddress, _linkTokenAmount, address(this).balance, "Contributing Link to the Smart Contract Total Funds.");
    }

    //Function: Get the amount a contributor has contributed
    function getWithdrawalAmount()
        public
        view
        returns(uint256 contributionLinkTokenAmountAfterCharge, uint256 indexOfContributor)
    {
        address senderAddress = msg.sender;
        uint256 totalFunds = link.balanceOf(address(this));
        uint256 contributorWeight;
        uint256 currentContributorWeight;
        uint256 amountContributed;
        uint256 totalFundsAtTimeOfContribution;
        uint256 totalWeight = 0;
        uint256 amountToWithdraw;
        uint256 contributionCharge;
        for(uint256 index = 0; index < contributors.length; index++) {
            amountContributed = addressToAmountContributed[contributors[index]];
            totalFundsAtTimeOfContribution = addressToTotalFundsAtTimeOfContribution[contributors[index]];
            currentContributorWeight = amountContributed * (totalFunds - totalFundsAtTimeOfContribution);
            totalWeight += currentContributorWeight;
            if(senderAddress == contributors[index]) {
                contributorWeight = currentContributorWeight;
                indexOfContributor = index;
            }
        }
        amountToWithdraw = (((contributorWeight * tenEight) / totalWeight) * totalFunds) / tenEight;
        contributionCharge = (percentageCharge * amountToWithdraw) / hundredPercent;
        contributionLinkTokenAmountAfterCharge = amountToWithdraw - contributionCharge;
        return (contributionLinkTokenAmountAfterCharge, indexOfContributor);
    }

    // Function: Allow contributors to withdraw their contributed ETH
    function withdrawContribution()
        external
        nonReentrant
        contributorExists
        withdrawalPossible
    {
        address senderAddress = msg.sender;
        (uint256 contributionLinkTokenAmountAfterCharge, uint256 indexOfContributor) = getWithdrawalAmount();
        if(contributionLinkTokenAmountAfterCharge > 0) {
            contributors[indexOfContributor] = contributors[contributors.length - 1];
            contributors.pop();
            addressToAmountContributed[senderAddress] = zeroValue;
            addressToTotalFundsAtTimeOfContribution[senderAddress] = zeroValue;
        }
        link.transfer(msg.sender, contributionLinkTokenAmountAfterCharge);
        emit StatusUpdate(senderAddress, contributionLinkTokenAmountAfterCharge, "Withdrawing Link contributed from Smart Contract Total Funds.");
    }

    //Function: Set the percentage to be charged by the contract upon withdrawal
    function updatePercentage(uint8 _percentage)
        external 
        onlyOwner
    {
        percentageCharge = _percentage;
    }

    //Function: Set the price for worth Ten
    function updateEntryPriceForSeven(uint16 _newPrice)
        external
        onlyOwner
    {
        entryPriceForWorthSeven = _newPrice;
    }

    //Function: Set the price for worth Ten
    function updateEntryPriceForSeventy(uint16 _newPrice)
        external
        onlyOwner
    {
        entryPriceForWorthSeventy = _newPrice;
    }

    //Function: Set the price for worth Ten
    function updateEntryPriceForSevenHundred(uint16 _newPrice)
        external
        onlyOwner
    {
        entryPriceForWorthSevenHundred = _newPrice;
    }

    // Function: Participate to win potentially 7 Link
    function playLotteryWorthSeven()
        external
        addressLinkBalanceCheck(entryPriceForWorthSeven)
        transferAllowedLink(entryPriceForWorthSeven * tenEighteen)
    {
        address senderAddress = msg.sender;
        link.transferFrom(senderAddress, address(this), entryPriceForWorthSeven * tenEighteen);
        rewardSLT(senderAddress, SLTRewardAmountSeven);
        addressToParticipationStatus[senderAddress] = true;
        addressToRequestId[senderAddress] = requestRandomWords();
        addressToDraw[senderAddress] = WorthSevenPotential;
        emit StatusUpdate(senderAddress, entryPriceForWorthSeven, "Paid to Participate in Draw Worth Hundred");
    }

    // Function: Participate to win potentially 70 Link
    function playLotteryWorthSeventy()
        external
        addressLinkBalanceCheck(entryPriceForWorthSeventy)
        transferAllowedLink(entryPriceForWorthSeventy * tenEighteen)
    {
        address senderAddress = msg.sender;
        link.transferFrom(senderAddress, address(this), entryPriceForWorthSeventy * tenEighteen);
        rewardSLT(senderAddress, SLTRewardAmountSeventy);
        addressToParticipationStatus[senderAddress] = true;
        addressToRequestId[senderAddress] = requestRandomWords();
        addressToDraw[senderAddress] = WorthSeventyPotential;
        emit StatusUpdate(senderAddress, entryPriceForWorthSeventy, "Paid to Participate in Draw Worth Thousand");
    }

    // Function: Participate to win potentially 700 Link
    function playLotteryWorthSevenHundred()
        external
        addressLinkBalanceCheck(entryPriceForWorthSevenHundred)
        transferAllowedLink(entryPriceForWorthSevenHundred * tenEighteen)
    {
        address senderAddress = msg.sender;
        link.transferFrom(senderAddress, address(this), entryPriceForWorthSevenHundred * tenEighteen);
        rewardSLT(senderAddress, SLTRewardAmountSevenHundred);
        addressToParticipationStatus[senderAddress] = true;
        addressToRequestId[senderAddress] = requestRandomWords();
        addressToDraw[senderAddress] = WorthSevenHundredPotential;
        emit StatusUpdate(senderAddress, entryPriceForWorthSevenHundred, "Paid to Participate in Draw Worth TenThousand");
    }

    // Function: Withdraw excess Link Tokens in Contract
    function withdrawExcessLinkTokens()
        external
        onlyOwner
        linkAmountCheck
    {
        link.transfer(msg.sender, link.balanceOf(address(this)));
    }

    // Function: Get random number
    function requestRandomWords()
        private
        returns(uint256 requestId)
    {
        requestId = requestRandomness(callbackGasLimit, requestConfirmations, numWords);
        s_requests[requestId] = RequestStatus({
            paid: VRF_V2_WRAPPER.calculateRequestPrice(callbackGasLimit),
            randomWords: new uint256[](0),
            fulfilled: false
        });
        return requestId;
    }

    // Function: Receive random number
    function fulfillRandomWords( uint256 _requestId, uint256[] memory _randomWords)
        internal
        override
    {
        require(s_requests[_requestId].paid > zeroValue, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
    }

    // Function: Get draw results
    function getFinalResult()
        public
        participationCheck
        randomNumberAvailable
    {
        uint256 LinkAmountToSend = zeroValue;
        uint256 randomNumber = zeroValue;
        address senderAddress = msg.sender;
        uint256 requestId = addressToRequestId[senderAddress];
        uint256 realRandomNumber = getRandomNumber(requestId);
        uint256 drawAmount = addressToDraw[senderAddress];
        if(drawAmount == WorthSevenPotential){
            randomNumber = realRandomNumber % worthSeven.length;
            LinkAmountToSend = worthSeven[randomNumber];
        } else if(drawAmount == WorthSeventyPotential){
            randomNumber = realRandomNumber % worthSeventy.length;
            LinkAmountToSend = worthSeventy[randomNumber];
        } else if(drawAmount == WorthSevenHundredPotential){
            randomNumber = realRandomNumber % worthSevenHundred.length;
            LinkAmountToSend = worthSevenHundred[randomNumber];
        }
        link.transfer(senderAddress, LinkAmountToSend * tenEighteen);
        addressToDraw[senderAddress] = zeroValue;
        emit StatusUpdate(senderAddress, LinkAmountToSend, "Link Token Amount Won From Participation");
    }


    // Function: Get random number for final result
    function getRandomNumber(uint256 _requestId)
        public
        view
        returns(uint256)
    {
        RequestStatus memory request = s_requests[_requestId];
        return (request.randomWords[0]);
    }

    // Function: Send SLT as airdrop
    function claimAirdropSLT()
        external
        airdropClaimed
        totalAirdropSentCheck
    {
        SLT.transfer(msg.sender, SLTAirdropAmount * tenEighteen);
    }

    // Function: Send SLT as reward
    function rewardSLT(address _recipientAddress, uint16 _SLTRewardAmount)
        private
        SLTAmountCheck
    {
        SLT.transfer(_recipientAddress, _SLTRewardAmount * tenEighteen);
    }

    // FUnction: Redeem SLT
    function redeemSLT(uint16 _SLTRedemptionAmount)
        external
        transferAllowedSLT(_SLTRedemptionAmount * tenEighteen)
        verifySLTRedemptionAmount
    {
        address senderAddress = msg.sender;
        SLT.transferFrom(senderAddress, address(this), _SLTRedemptionAmount * tenEighteen);
        uint256 LinkAmountToSend = convertDollarToLink((((_SLTRedemptionAmount * tenEight) / SLTRedemptionFee) * SLTPricePerRedemption) / tenEight);
        link.transfer(senderAddress, LinkAmountToSend);
    }
    
    // Function: Set Reward Token Address
    function updateSLTAddress(address _SLTAddress)
        external
        onlyOwner
    {
        SLTAddress = _SLTAddress;
        SLT = IERC20(SLTAddress);
    }

    // Function: Update reward token worth
    function updateSLTPricePerRedemption(uint16 _SLTPricePerRedemption)
        external
        onlyOwner
    {
        SLTPricePerRedemption = _SLTPricePerRedemption;
    }

    // Function: Update reward token redemption price
    function updateSLTRedemptionFee(uint16 _SLTRedemptionFee)
        external
        onlyOwner
    {
        SLTRedemptionFee = _SLTRedemptionFee;
    }
    
    // Function: Update reward token redemption price
    function updateSLTAirdropLimit(uint16 _SLTAirdropLimit)
        external
        onlyOwner
    {
        totalAirdrop = _SLTAirdropLimit;
    }

    // Function: Update Reward Token Amount
    function updateSLTRewardHundredAmount(uint16 _SLTRewardAmount)
        external
        onlyOwner
    {
        SLTRewardAmountSeven = _SLTRewardAmount;
    }

    // Function: Update Reward Token Amount
    function updateSLTRewardThousandAmount(uint16 _SLTRewardAmount)
        external
        onlyOwner
    {
        SLTRewardAmountSeventy = _SLTRewardAmount;
    }

    // Function: Update Reward Token Amount
    function updateSLTRewardTenThousandAmount(uint16 _SLTRewardAmount)
        external
        onlyOwner
    {
        SLTRewardAmountSevenHundred = _SLTRewardAmount;
    }

    // Function: Update Airdrop Token Amount
    function updateSLTAirdropAmount(uint16 _newTokenAmount)
        external
        onlyOwner
    {
        SLTAirdropAmount = _newTokenAmount;
    }
}