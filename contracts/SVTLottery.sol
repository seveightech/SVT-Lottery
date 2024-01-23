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
    uint32 public totalAirdrop = 10000;

    // Reward Token variables
    uint16 public SLTRewardAmountTen = 1;
    uint16 public SLTRewardAmountHundred = 10;
    uint16 public SLTRewardAmountThousand = 25;
    uint16 public SLTRewardAmountTenThousand = 250;
    uint16 public SLTRedemptionFee = 5;
    uint16 public SLTAirdropAmount = 5;
    uint16 public SLTPricePerRedemption = 1;

    // Conversion Prices
    uint256 private tenEighteen = 10**18;
    uint256 private tenEight = 10**8;
    uint256 private tenTen = 10**10;
    uint8 private hundredPercent = 100;

    // Prices for each category
    uint16 public entryPriceForWorthHundred = 23;
    uint16 public entryPriceForWorthThousand = 43;
    uint16 public entryPriceForWorthTenThousand = 283;

    // Potential Prize Amounts
    uint16 public WorthTenPotential = 10;
    uint16 public WorthHundredPotential = 100;
    uint16 public WorthThousandPotential = 1000;
    uint16 public WorthTenThousandPotential = 10000;

    // Link Token fee
    uint16 public linkTokenFee = 2;

    // Zero Value
    uint8 private zeroValue = 0;

    // Arrays for prizes
    uint256[] private worthHundred = [
        5, 1, 3, 30, 7, 1, 100, 1, 1, 10
    ];
    uint256[] private worthThousand = [
        10, 2, 8, 1, 9, 3, 6, 50, 7, 4, 5, 20, 3, 1, 4, 25, 2, 3, 13, 6, 1000, 5, 12, 3, 1, 9, 3, 10, 4, 5
    ];
    uint256[] private worthTenThousand = [
        23, 1, 12, 1, 20, 300, 10, 7, 23, 4, 20, 11, 290, 19, 18, 10, 2, 23, 50, 23, 1, 17, 16, 15, 14, 200, 11, 13, 1, 100, 12, 13, 12, 11, 10, 10000, 1, 1, 1, 20
    ];

    // address for airdrop tokens
    address public SLTAddress;

    // address WRAPPER - hardcoded for Sepolia
    address public wrapperAddress = 0xab18414CD93297B0d12ac29E63Ca20f515b3DB46; // 0x5A861794B927983406fCE1D062e00b9368d97Df6

    // Link Token Address - hardcoded for Sepolia
    address public linkTokenAddress = 0x779877A7B0D9E8603169DdbD7836e478b4624789; // 0x514910771AF9Ca656af840dff83E8264EcF986CA

    //address public priceFeedMainnet = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public priceFeedSepolia = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    //address public priceFeedGeorli = 0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e;

    // Contributors List
    address[] public contributors;

    // Mapping for reentrancy guard to prevent recursive calls
    mapping (address => bool) private addressAccessLocked;

    // Mapping for Request ID to Random Number Stuct
    mapping (uint256 => RequestStatus) public s_requests;

    // Mapping for Address to Participation Status
    mapping (address => bool) private addressToParticipationStatus;

    // Mapping for Address to Requested Random Number Function
    mapping (address => bool) private addressToRandomnessCheck;

    // Mapping for Address to Airdrop claimed
    mapping (address => bool) addressToAidropClaimed;

    // <appimg for Link Token Fee Check
    mapping (address => bool) private addressToLinkTokenFeePaid;

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
    event Contribution(address indexed contributor, uint256 ethAmount, uint256 totalContributions, string reason);
    event StatusUpdate(address indexed participant, uint256 Amount, string reason);
    event LinkTokensReceived(address indexed sender, uint256 linkTokenAmount, uint256 totalLinkTokensInContract, string reason);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords, uint256 payment);

    // Modifier: Prevents reentrancy attacks
    modifier nonReentrant() {
        require(!addressAccessLocked[msg.sender], "Reentrancy guard: locked");
        addressAccessLocked[msg.sender] = true;
        _;
        addressAccessLocked[msg.sender] = false;
    }

    // Modifier: Require entry amount to be equal to or greater than entry price
    modifier entryPriceCheck(uint256 _amountSent, uint256 _amountRequired) {
        uint256 ethAmountRequired = convertDollarToEth(_amountRequired);
        require(_amountSent >= ethAmountRequired, "Amount Paid is less than Entry price");
        _;
    }

    // Modifier: Require entry amount to be equal to or greater than entry price
    modifier addressBalanceCheck(uint256 _amountRequired) {
        uint256 ethAmountRequired = convertDollarToEth(_amountRequired);
        require(address(this).balance >= ethAmountRequired, "Not enough Value in contract to enter this draw");
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
        require(totalAirdropSent < totalAirdrop, "Airdrop No Longer Possible");
        _;
        totalAirdropSent += SLTAirdropAmount;
    }

    // Modifier: Check if withdrawal is possible
    modifier withdrawalPossible() {
        require(address(this).balance > addressToTotalFundsAtTimeOfContribution[msg.sender], "You are not eligible to withdraw");
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

    // Modifier: Check if Link Token Fee has been paid
    modifier linkTokenFeePaid() {
        require(addressToLinkTokenFeePaid[msg.sender] == true, "Link token fee not paid");
        _;
        addressToLinkTokenFeePaid[msg.sender] = false;
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
        require(s_requests[_requestId].fulfilled == true, "request not found");
        _;
    }

    // Modifier: Range check for contributors list index
    modifier randomNumberRequestedCheck() {
        require(addressToRandomnessCheck[msg.sender] == false, "You have already requested for a Random Number");
        _;
        addressToRandomnessCheck[msg.sender] = true;
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
    function checkEthPrice()
        internal
        view
        returns(uint256)
    {
        (,int256 price,,,) = priceFeed.latestRoundData();
        uint256 ethPrice = uint256(price) * tenTen;
        return ethPrice;
    }

    // Function: Convert ETH to dollar equivalent
    function convertEthToDollar(uint256 _ethAmountInWei)
        internal 
        view 
        returns(uint256)
    {
        uint256 currentEthPrice = checkEthPrice();
        uint256 dollarEquivalent = (_ethAmountInWei * currentEthPrice) / tenEighteen;
        return dollarEquivalent;
    }

    // Function: Convert dollar to ETH equivalent
    function convertDollarToEth(uint256 dollarAmount)
        internal
        view
        returns(uint256) 
    {
        uint256 currentEthPrice = checkEthPrice();
        uint256 ethEquivalent = ((dollarAmount * tenEighteen) / (currentEthPrice / tenTen)) * tenEight;
        return ethEquivalent;
    }

    // Function: Allow contributors to contribute ETH to the smart contract
        function contribute()
        external 
        payable
        nonReentrant
        contributorDoesNotExist
    {
        address senderAddress = msg.sender;
        addressToTotalFundsAtTimeOfContribution[senderAddress] = address(this).balance - msg.value;
        addressToAmountContributed[senderAddress] = msg.value;
        contributors.push(senderAddress);
        emit Contribution(senderAddress, msg.value, address(this).balance, "Contributing ETH to the Smart Contract Total Funds.");
    }

    //Function: Get the amount a contributor has contributed
    function getWithdrawalAmount()
        public
        view
        returns(uint256 contributionEthAmountAfterCharge, uint256 indexOfContributor)
    {
        address senderAddress = msg.sender;
        uint256 totalFunds = address(this).balance;
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
        contributionEthAmountAfterCharge = amountToWithdraw - contributionCharge;
        return (contributionEthAmountAfterCharge, indexOfContributor);
    }

    // Function: Allow contributors to withdraw their contributed ETH
    function withdrawContribution()
        external
        nonReentrant
        contributorExists
        withdrawalPossible
    {
        address senderAddress = msg.sender;
        (uint256 contributionEthAmountAfterCharge, uint256 indexOfContributor) = getWithdrawalAmount();
        if(contributionEthAmountAfterCharge > 0) {
            contributors[indexOfContributor] = contributors[contributors.length - 1];
            contributors.pop();
            addressToAmountContributed[senderAddress] = zeroValue;
            addressToTotalFundsAtTimeOfContribution[senderAddress] = zeroValue;
        }
        payable(senderAddress).transfer(contributionEthAmountAfterCharge);
        emit StatusUpdate(senderAddress, contributionEthAmountAfterCharge, "Withdrawing ETH contributed from Smart Contract Total Funds.");
    }

    //Function: Set the percentage to be charged by the contract upon withdrawal
    function updatePercentage(uint8 _percentage)
        external 
        onlyOwner
    {
        percentageCharge = _percentage;
    }

    //Function: Set the price for worth Ten
    function updatePriceForHundred(uint16 _newPrice)
        external
        onlyOwner
    {
        entryPriceForWorthHundred = _newPrice;
    }

    //Function: Set the price for worth Ten
    function updatePriceForThousand(uint16 _newPrice)
        external
        onlyOwner
    {
        entryPriceForWorthThousand = _newPrice;
    }

    //Function: Set the price for worth Ten
    function updatePriceForTenThousand(uint16 _newPrice)
        external
        onlyOwner
    {
        entryPriceForWorthTenThousand = _newPrice;
    }

    // Function: Participate to win potentially $10
    function playLotteryWorthHundred()
        external
        payable
        entryPriceCheck(msg.value, entryPriceForWorthHundred) 
        addressBalanceCheck(entryPriceForWorthHundred)
        linkTokenFeePaid
    {
        address senderAddress = msg.sender;
        rewardSLT(senderAddress, SLTRewardAmountHundred);
        addressToParticipationStatus[senderAddress] = true;
        addressToRandomnessCheck[senderAddress] = false;
        addressToRequestId[senderAddress] = requestRandomWords();
        addressToDraw[senderAddress] = WorthHundredPotential;
        emit StatusUpdate(senderAddress, msg.value, "Paid to Participate in Draw Worth Hundred");
    }

    // Function: Participate to win potentially $10
    function playLotteryWorthThousand()
        external
        payable
        entryPriceCheck(msg.value, entryPriceForWorthThousand) 
        addressBalanceCheck(entryPriceForWorthThousand)
        linkTokenFeePaid
    {
        address senderAddress = msg.sender;
        rewardSLT(senderAddress, SLTRewardAmountThousand);
        addressToParticipationStatus[senderAddress] = true;
        addressToRandomnessCheck[senderAddress] = false;
        addressToRequestId[senderAddress] = requestRandomWords();
        addressToDraw[senderAddress] = WorthThousandPotential;
        emit StatusUpdate(senderAddress, msg.value, "Paid to Participate in Draw Worth Thousand");
    }

    // Function: Participate to win potentially $10
    function playLotteryWorthTenThousand()
        external
        payable
        entryPriceCheck(msg.value, entryPriceForWorthTenThousand) 
        addressBalanceCheck(entryPriceForWorthTenThousand)
        linkTokenFeePaid
    {
        address senderAddress = msg.sender;
        rewardSLT(senderAddress, SLTRewardAmountTenThousand);
        addressToParticipationStatus[senderAddress] = true;
        addressToRandomnessCheck[senderAddress] = false;
        addressToRequestId[senderAddress] = requestRandomWords();
        addressToDraw[senderAddress] = WorthTenThousandPotential;
        emit StatusUpdate(senderAddress, msg.value, "Paid to Participate in Draw Worth TenThousand");
    }

    // Function: Receive Link Tokens
    function payLinkTokenFee()
        external
        transferAllowedLink(linkTokenFee * tenEighteen)
    {
        link.transferFrom(msg.sender, address(this), linkTokenFee * tenEighteen);
        addressToLinkTokenFeePaid[msg.sender] = true;
    }

    //Function: Set Link token fee
    function updateLinkTokenFee(uint16 _amountOfLink)
        external
        onlyOwner
    {
        linkTokenFee = _amountOfLink;
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
        randomNumberRequestedCheck
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
        uint256 amountToRedeem = zeroValue;
        uint256 ethAmountToSend = zeroValue;
        uint256 randomNumber = zeroValue;
        address senderAddress = msg.sender;
        uint256 requestId = addressToRequestId[senderAddress];
        uint256 realRandomNumber = getRandomNumber(requestId);
        uint256 drawAmount = addressToDraw[senderAddress];
        if(drawAmount == WorthHundredPotential){
            randomNumber = realRandomNumber % worthHundred.length;
            amountToRedeem = worthHundred[randomNumber];
            ethAmountToSend = convertDollarToEth(amountToRedeem);
        } else if(drawAmount == WorthThousandPotential){
            randomNumber = realRandomNumber % worthThousand.length;
            amountToRedeem = worthThousand[randomNumber];
            ethAmountToSend = convertDollarToEth(amountToRedeem);
        } else if(drawAmount == WorthTenThousandPotential){
            randomNumber = realRandomNumber % worthTenThousand.length;
            amountToRedeem = worthTenThousand[randomNumber];
            ethAmountToSend = convertDollarToEth(amountToRedeem);
        }
        payable(senderAddress).transfer(ethAmountToSend);
        addressToDraw[senderAddress] = zeroValue;
        addressToRandomnessCheck[senderAddress] = false;
        emit StatusUpdate(senderAddress, amountToRedeem, "Dollar Amount Won From Participation");
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
        uint256 ethAmountToSend = convertDollarToEth((((_SLTRedemptionAmount * tenEight) / SLTRedemptionFee) * SLTPricePerRedemption) / tenEight);
        payable(senderAddress).transfer(ethAmountToSend);
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

    // Function: Update Reward Token Amount
    function updateSLTRewardTenAmount(uint16 _SLTRewardAmount)
        external
        onlyOwner
    {
        SLTRewardAmountTen = _SLTRewardAmount;
    }

    // Function: Update Reward Token Amount
    function updateSLTRewardHundredAmount(uint16 _SLTRewardAmount)
        external
        onlyOwner
    {
        SLTRewardAmountHundred = _SLTRewardAmount;
    }

    // Function: Update Reward Token Amount
    function updateSLTRewardThousandAmount(uint16 _SLTRewardAmount)
        external
        onlyOwner
    {
        SLTRewardAmountThousand = _SLTRewardAmount;
    }

    // Function: Update Reward Token Amount
    function updateSLTRewardTenThousandAmount(uint16 _SLTRewardAmount)
        external
        onlyOwner
    {
        SLTRewardAmountTenThousand = _SLTRewardAmount;
    }

    // Function: Update Airdrop Token Amount
    function updateSLTAirdropAmount(uint16 _newTokenAmount)
        external
        onlyOwner
    {
        SLTAirdropAmount = _newTokenAmount;
    }
}