# Decentralized Review Protocol

An enhanced peer review system built on the Stacks blockchain using Clarity smart contracts.

## Features

### 1. Review Status Tracking
- Papers progress through defined statuses: Submitted → Under Review → Reviewed → Accepted/Rejected
- Minimum review requirements before papers can be accepted or rejected
- Automatic status updates based on review activity

### 2. Access Control & Permissions
- Reviewer registration system with expertise tracking
- Only registered and active reviewers can submit reviews
- Authors cannot review their own papers
- Duplicate review prevention
- Admin controls for reviewer management

### 3. Enhanced Data Storage
- Comprehensive paper metadata (title, abstract, keywords, URI)
- Multi-dimensional review ratings (technical quality, novelty, clarity, overall)
- Extended feedback capacity (1000 characters)
- Review timestamps and submission tracking
- Reviewer reputation and statistics

### 4. Economic Incentives
- Paper submission fees (1 STX)
- Review rewards (0.5 STX per review)
- Automatic fee collection and reward distribution
- Reputation scoring system for reviewers
- Contract balance management

## Contract Functions

### Public Functions

#### Reviewer Management
- `register-reviewer(expertise)` - Register as a reviewer with expertise area
- `deactivate-reviewer(reviewer)` - Deactivate a reviewer (owner or self only)

#### Paper Management
- `submit-paper(title, abstract, keywords, uri)` - Submit a paper for review (requires fee)
- `update-paper-status(paper-id, new-status)` - Update paper status (owner only)

#### Review Management
- `submit-review(paper-id, technical-quality, novelty, clarity, overall-rating, feedback)` - Submit a comprehensive review

#### Emergency Functions
- `emergency-withdraw(amount)` - Emergency fund withdrawal (owner only)

### Read-Only Functions
- `get-paper(paper-id)` - Get paper details
- `get-review(paper-id, reviewer)` - Get specific review
- `get-reviewer-info(reviewer)` - Get reviewer information
- `get-paper-count()` - Get total number of papers
- `has-reviewed(reviewer, paper-id)` - Check if reviewer has reviewed paper
- `get-contract-balance()` - Get contract balance
- `is-reviewer-registered(reviewer)` - Check if user is registered reviewer
- `get-paper-status(paper-id)` - Get paper status
- `get-average-rating(paper-id)` - Calculate average rating for paper

## Constants

### Status Codes
- `STATUS-SUBMITTED` (1) - Paper submitted
- `STATUS-UNDER-REVIEW` (2) - Paper under review
- `STATUS-REVIEWED` (3) - Review process complete
- `STATUS-ACCEPTED` (4) - Paper accepted
- `STATUS-REJECTED` (5) - Paper rejected

### Economic Parameters
- `SUBMISSION-FEE` - 1,000,000 microSTX (1 STX)
- `REVIEW-REWARD` - 500,000 microSTX (0.5 STX)
- `MIN-REVIEWS` - 3 reviews required before acceptance/rejection

### Error Codes
- `ERR-UNAUTHORIZED` (100) - Unauthorized access
- `ERR-NOT-FOUND` (101) - Resource not found
- `ERR-INVALID-STATUS` (102) - Invalid status or rating
- `ERR-ALREADY-REVIEWED` (103) - Duplicate review attempt
- `ERR-INSUFFICIENT-BALANCE` (104) - Insufficient balance
- `ERR-SELF-REVIEW` (105) - Self-review attempt
- `ERR-NOT-REGISTERED` (106) - Reviewer not registered

## Usage Example

```clarity
;; Register as a reviewer
(contract-call? .ReviewPool register-reviewer "Machine Learning Expert")

;; Submit a paper
(contract-call? .ReviewPool submit-paper 
  "Deep Learning in Healthcare" 
  "This paper explores applications of deep learning in medical diagnosis"
  "deep learning, healthcare, AI"
  "https://example.com/paper.pdf")

;; Submit a review
(contract-call? .ReviewPool submit-review 
  u0    ;; paper-id
  u4    ;; technical-quality (1-5)
  u3    ;; novelty (1-5)
  u5    ;; clarity (1-5)
  u4    ;; overall-rating (1-5)
  "Well-written paper with solid methodology and clear presentation")
```

## Testing

Run the test suite to verify all functionality:

```bash
npm test
```

The test suite covers:
- Reviewer registration and management
- Paper submission with fee payment
- Review submission with validation
- Status management and access control
- Economic incentive mechanisms
- Error handling and edge cases

## Security Features

- Access control for all critical functions
- Input validation for ratings and status codes
- Prevention of self-reviews and duplicate reviews
- Economic incentives aligned with quality participation
- Emergency controls for contract owner
- Comprehensive error handling

## Future Enhancements

The contract provides a solid foundation for additional features such as:
- Anonymous review options
- Advanced reputation algorithms
- Integration with external storage (IPFS)
- Cross-chain compatibility
- Governance mechanisms
- Advanced search and filtering capabilities
