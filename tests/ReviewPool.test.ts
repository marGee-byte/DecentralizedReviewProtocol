import { describe, expect, it, beforeEach } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const wallet1 = accounts.get("wallet_1")!;
const wallet2 = accounts.get("wallet_2")!;
const wallet3 = accounts.get("wallet_3")!;

describe("ReviewPool Contract Tests", () => {
  beforeEach(() => {
    // Reset simnet state before each test
    simnet.setEpoch("3.0");
  });

  describe("Reviewer Registration", () => {
    it("should allow users to register as reviewers", () => {
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "register-reviewer",
        [Cl.stringUtf8("Machine Learning Expert")],
        wallet1
      );
      expect(result).toBeOk(Cl.stringAscii("Reviewer registered successfully"));
    });

    it("should store reviewer information correctly", () => {
      // Register reviewer
      simnet.callPublicFn(
        "ReviewPool",
        "register-reviewer",
        [Cl.stringUtf8("AI Research")],
        wallet1
      );

      // Check reviewer info
      const { result } = simnet.callReadOnlyFn(
        "ReviewPool",
        "get-reviewer-info",
        [Cl.principal(wallet1)],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          expertise: Cl.stringUtf8("AI Research"),
          "reputation-score": Cl.uint(100),
          "total-reviews": Cl.uint(0),
          "is-active": Cl.bool(true)
        })
      );
    });

    it("should check if reviewer is registered", () => {
      // Before registration
      let { result } = simnet.callReadOnlyFn(
        "ReviewPool",
        "is-reviewer-registered",
        [Cl.principal(wallet1)],
        wallet1
      );
      expect(result).toBeBool(false);

      // Register reviewer
      simnet.callPublicFn(
        "ReviewPool",
        "register-reviewer",
        [Cl.stringUtf8("Data Science")],
        wallet1
      );

      // After registration
      ({ result } = simnet.callReadOnlyFn(
        "ReviewPool",
        "is-reviewer-registered",
        [Cl.principal(wallet1)],
        wallet1
      ));
      expect(result).toBeBool(true);
    });
  });

  describe("Paper Submission", () => {
    it("should allow paper submission with fee payment", () => {
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "submit-paper",
        [
          Cl.stringUtf8("Deep Learning in Healthcare"),
          Cl.stringUtf8("This paper explores the application of deep learning techniques in medical diagnosis and treatment planning."),
          Cl.stringUtf8("deep learning, healthcare, AI, medical diagnosis"),
          Cl.stringUtf8("https://example.com/paper1.pdf")
        ],
        wallet1
      );
      expect(result).toBeOk(Cl.uint(0));
    });

    it("should store paper with correct metadata", () => {
      // Submit paper
      simnet.callPublicFn(
        "ReviewPool",
        "submit-paper",
        [
          Cl.stringUtf8("Blockchain Consensus"),
          Cl.stringUtf8("Analysis of various consensus mechanisms in blockchain networks."),
          Cl.stringUtf8("blockchain, consensus, distributed systems"),
          Cl.stringUtf8("https://example.com/paper2.pdf")
        ],
        wallet1
      );

      // Check paper data
      const { result } = simnet.callReadOnlyFn(
        "ReviewPool",
        "get-paper",
        [Cl.uint(0)],
        wallet1
      );

      expect(result).toBeSome(
        Cl.tuple({
          author: Cl.principal(wallet1),
          title: Cl.stringUtf8("Blockchain Consensus"),
          abstract: Cl.stringUtf8("Analysis of various consensus mechanisms in blockchain networks."),
          keywords: Cl.stringUtf8("blockchain, consensus, distributed systems"),
          uri: Cl.stringUtf8("https://example.com/paper2.pdf"),
          status: Cl.uint(1), // STATUS-SUBMITTED
          "submission-time": Cl.uint(simnet.blockHeight),
          "review-count": Cl.uint(0),
          "total-rating": Cl.uint(0)
        })
      );
    });

    it("should increment paper counter", () => {
      // Submit first paper
      simnet.callPublicFn(
        "ReviewPool",
        "submit-paper",
        [
          Cl.stringUtf8("Paper 1"),
          Cl.stringUtf8("Abstract 1"),
          Cl.stringUtf8("keywords1"),
          Cl.stringUtf8("https://example.com/1.pdf")
        ],
        wallet1
      );

      // Submit second paper
      simnet.callPublicFn(
        "ReviewPool",
        "submit-paper",
        [
          Cl.stringUtf8("Paper 2"),
          Cl.stringUtf8("Abstract 2"),
          Cl.stringUtf8("keywords2"),
          Cl.stringUtf8("https://example.com/2.pdf")
        ],
        wallet2
      );

      const { result } = simnet.callReadOnlyFn(
        "ReviewPool",
        "get-paper-count",
        [],
        wallet1
      );
      expect(result).toBeUint(2);
    });
  });

  describe("Review Submission", () => {
    beforeEach(() => {
      // Register reviewers
      simnet.callPublicFn(
        "ReviewPool",
        "register-reviewer",
        [Cl.stringUtf8("Expert Reviewer 1")],
        wallet2
      );
      simnet.callPublicFn(
        "ReviewPool",
        "register-reviewer",
        [Cl.stringUtf8("Expert Reviewer 2")],
        wallet3
      );

      // Submit a paper
      simnet.callPublicFn(
        "ReviewPool",
        "submit-paper",
        [
          Cl.stringUtf8("Test Paper"),
          Cl.stringUtf8("Test Abstract"),
          Cl.stringUtf8("test, keywords"),
          Cl.stringUtf8("https://example.com/test.pdf")
        ],
        wallet1
      );
    });

    it("should allow registered reviewers to submit reviews", () => {
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "submit-review",
        [
          Cl.uint(0), // paper-id
          Cl.uint(4), // technical-quality
          Cl.uint(3), // novelty
          Cl.uint(5), // clarity
          Cl.uint(4), // overall-rating
          Cl.stringUtf8("This is a well-written paper with good technical content.")
        ],
        wallet2
      );
      expect(result).toBeOk(Cl.stringAscii("Review submitted successfully"));
    });

    it("should prevent unregistered users from reviewing", () => {
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "submit-review",
        [
          Cl.uint(0),
          Cl.uint(4),
          Cl.uint(3),
          Cl.uint(5),
          Cl.uint(4),
          Cl.stringUtf8("Unauthorized review attempt")
        ],
        accounts.get("wallet_4")! // Unregistered user
      );
      expect(result).toBeErr(Cl.uint(106)); // ERR-NOT-REGISTERED
    });

    it("should prevent authors from reviewing their own papers", () => {
      // Register the author as a reviewer
      simnet.callPublicFn(
        "ReviewPool",
        "register-reviewer",
        [Cl.stringUtf8("Author Reviewer")],
        wallet1
      );

      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "submit-review",
        [
          Cl.uint(0),
          Cl.uint(5),
          Cl.uint(5),
          Cl.uint(5),
          Cl.uint(5),
          Cl.stringUtf8("Self review attempt")
        ],
        wallet1 // Author trying to review own paper
      );
      expect(result).toBeErr(Cl.uint(105)); // ERR-SELF-REVIEW
    });

    it("should prevent duplicate reviews from same reviewer", () => {
      // Submit first review
      simnet.callPublicFn(
        "ReviewPool",
        "submit-review",
        [
          Cl.uint(0),
          Cl.uint(4),
          Cl.uint(3),
          Cl.uint(5),
          Cl.uint(4),
          Cl.stringUtf8("First review")
        ],
        wallet2
      );

      // Attempt duplicate review
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "submit-review",
        [
          Cl.uint(0),
          Cl.uint(3),
          Cl.uint(2),
          Cl.uint(4),
          Cl.uint(3),
          Cl.stringUtf8("Duplicate review attempt")
        ],
        wallet2
      );
      expect(result).toBeErr(Cl.uint(103)); // ERR-ALREADY-REVIEWED
    });

    it("should validate rating ranges", () => {
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "submit-review",
        [
          Cl.uint(0),
          Cl.uint(6), // Invalid rating > 5
          Cl.uint(3),
          Cl.uint(5),
          Cl.uint(4),
          Cl.stringUtf8("Invalid rating test")
        ],
        wallet2
      );
      expect(result).toBeErr(Cl.uint(102)); // ERR-INVALID-STATUS
    });

    it("should update paper statistics after review", () => {
      // Submit review
      simnet.callPublicFn(
        "ReviewPool",
        "submit-review",
        [
          Cl.uint(0),
          Cl.uint(4),
          Cl.uint(3),
          Cl.uint(5),
          Cl.uint(4),
          Cl.stringUtf8("Good paper")
        ],
        wallet2
      );

      // Check updated paper data
      const { result } = simnet.callReadOnlyFn(
        "ReviewPool",
        "get-paper",
        [Cl.uint(0)],
        wallet1
      );

      const paperData = result.expectSome();
      expect(Cl.unwrap(paperData)["review-count"]).toBeUint(1);
      expect(Cl.unwrap(paperData)["total-rating"]).toBeUint(4);
      expect(Cl.unwrap(paperData)["status"]).toBeUint(2); // STATUS-UNDER-REVIEW
    });

    it("should update reviewer statistics after review", () => {
      // Submit review
      simnet.callPublicFn(
        "ReviewPool",
        "submit-review",
        [
          Cl.uint(0),
          Cl.uint(4),
          Cl.uint(3),
          Cl.uint(5),
          Cl.uint(4),
          Cl.stringUtf8("Quality review")
        ],
        wallet2
      );

      // Check updated reviewer data
      const { result } = simnet.callReadOnlyFn(
        "ReviewPool",
        "get-reviewer-info",
        [Cl.principal(wallet2)],
        wallet2
      );

      const reviewerData = result.expectSome();
      expect(Cl.unwrap(reviewerData)["total-reviews"]).toBeUint(1);
      expect(Cl.unwrap(reviewerData)["reputation-score"]).toBeUint(110); // 100 + 10
    });
  });

  describe("Status Management", () => {
    beforeEach(() => {
      // Register reviewers
      simnet.callPublicFn("ReviewPool", "register-reviewer", [Cl.stringUtf8("Reviewer 1")], wallet1);
      simnet.callPublicFn("ReviewPool", "register-reviewer", [Cl.stringUtf8("Reviewer 2")], wallet2);
      simnet.callPublicFn("ReviewPool", "register-reviewer", [Cl.stringUtf8("Reviewer 3")], wallet3);

      // Submit paper
      simnet.callPublicFn(
        "ReviewPool",
        "submit-paper",
        [
          Cl.stringUtf8("Status Test Paper"),
          Cl.stringUtf8("Abstract for status testing"),
          Cl.stringUtf8("status, test"),
          Cl.stringUtf8("https://example.com/status.pdf")
        ],
        accounts.get("wallet_4")!
      );
    });

    it("should require minimum reviews before accepting/rejecting", () => {
      // Try to accept paper without enough reviews
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "update-paper-status",
        [Cl.uint(0), Cl.uint(4)], // STATUS-ACCEPTED
        deployer
      );
      expect(result).toBeErr(Cl.uint(102)); // ERR-INVALID-STATUS
    });

    it("should allow status update after sufficient reviews", () => {
      // Submit 3 reviews
      simnet.callPublicFn("ReviewPool", "submit-review", 
        [Cl.uint(0), Cl.uint(4), Cl.uint(3), Cl.uint(5), Cl.uint(4), Cl.stringUtf8("Review 1")], wallet1);
      simnet.callPublicFn("ReviewPool", "submit-review", 
        [Cl.uint(0), Cl.uint(3), Cl.uint(4), Cl.uint(4), Cl.uint(4), Cl.stringUtf8("Review 2")], wallet2);
      simnet.callPublicFn("ReviewPool", "submit-review", 
        [Cl.uint(0), Cl.uint(5), Cl.uint(3), Cl.uint(4), Cl.uint(4), Cl.stringUtf8("Review 3")], wallet3);

      // Now accept the paper
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "update-paper-status",
        [Cl.uint(0), Cl.uint(4)], // STATUS-ACCEPTED
        deployer
      );
      expect(result).toBeOk(Cl.stringAscii("Paper status updated"));
    });

    it("should only allow contract owner to update status", () => {
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "update-paper-status",
        [Cl.uint(0), Cl.uint(3)], // STATUS-REVIEWED
        wallet1 // Not the contract owner
      );
      expect(result).toBeErr(Cl.uint(100)); // ERR-UNAUTHORIZED
    });
  });

  describe("Economic Incentives", () => {
    it("should track contract balance from fees", () => {
      // Submit paper (pays fee)
      simnet.callPublicFn(
        "ReviewPool",
        "submit-paper",
        [
          Cl.stringUtf8("Fee Test Paper"),
          Cl.stringUtf8("Testing fee collection"),
          Cl.stringUtf8("fee, test"),
          Cl.stringUtf8("https://example.com/fee.pdf")
        ],
        wallet1
      );

      const { result } = simnet.callReadOnlyFn(
        "ReviewPool",
        "get-contract-balance",
        [],
        wallet1
      );
      expect(result).toBeUint(1000000); // SUBMISSION-FEE
    });

    it("should calculate average rating correctly", () => {
      // Register reviewers and submit paper
      simnet.callPublicFn("ReviewPool", "register-reviewer", [Cl.stringUtf8("Reviewer 1")], wallet2);
      simnet.callPublicFn("ReviewPool", "register-reviewer", [Cl.stringUtf8("Reviewer 2")], wallet3);
      
      simnet.callPublicFn(
        "ReviewPool",
        "submit-paper",
        [Cl.stringUtf8("Rating Test"), Cl.stringUtf8("Abstract"), Cl.stringUtf8("test"), Cl.stringUtf8("https://example.com/rating.pdf")],
        wallet1
      );

      // Submit reviews with ratings 4 and 2
      simnet.callPublicFn("ReviewPool", "submit-review", 
        [Cl.uint(0), Cl.uint(4), Cl.uint(3), Cl.uint(5), Cl.uint(4), Cl.stringUtf8("Good")], wallet2);
      simnet.callPublicFn("ReviewPool", "submit-review", 
        [Cl.uint(0), Cl.uint(2), Cl.uint(1), Cl.uint(3), Cl.uint(2), Cl.stringUtf8("Poor")], wallet3);

      // Check average rating: (4 + 2) / 2 = 3
      const { result } = simnet.callReadOnlyFn(
        "ReviewPool",
        "get-average-rating",
        [Cl.uint(0)],
        wallet1
      );
      expect(result).toBeSome(Cl.uint(3));
    });
  });

  describe("Access Control", () => {
    it("should allow reviewer deactivation by owner", () => {
      // Register reviewer
      simnet.callPublicFn("ReviewPool", "register-reviewer", [Cl.stringUtf8("Test Reviewer")], wallet1);

      // Deactivate by owner
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "deactivate-reviewer",
        [Cl.principal(wallet1)],
        deployer
      );
      expect(result).toBeOk(Cl.stringAscii("Reviewer deactivated"));

      // Check if reviewer is still registered (should be false due to deactivation)
      const { result: isRegistered } = simnet.callReadOnlyFn(
        "ReviewPool",
        "is-reviewer-registered",
        [Cl.principal(wallet1)],
        wallet1
      );
      expect(isRegistered).toBeBool(false);
    });

    it("should allow self-deactivation", () => {
      // Register reviewer
      simnet.callPublicFn("ReviewPool", "register-reviewer", [Cl.stringUtf8("Self Deactivate")], wallet1);

      // Self-deactivate
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "deactivate-reviewer",
        [Cl.principal(wallet1)],
        wallet1
      );
      expect(result).toBeOk(Cl.stringAscii("Reviewer deactivated"));
    });

    it("should prevent unauthorized deactivation", () => {
      // Register reviewer
      simnet.callPublicFn("ReviewPool", "register-reviewer", [Cl.stringUtf8("Protected Reviewer")], wallet1);

      // Try to deactivate from different account
      const { result } = simnet.callPublicFn(
        "ReviewPool",
        "deactivate-reviewer",
        [Cl.principal(wallet1)],
        wallet2
      );
      expect(result).toBeErr(Cl.uint(100)); // ERR-UNAUTHORIZED
    });
  });
});