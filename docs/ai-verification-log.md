# AI assistant task | what I asked, and how I checked it

The week 1 brief asked me to have an AI assistant explain four topics, then check the explanations against my AWS account and AWS documentation. The assistant was **Claude (Anthropic's Opus 5.5 model, in Claude Code)**, used on 13 November 2026. Its answers, after checking, became sections 1, 2, 7, 8 and 10 of [report.md](report.md).

An explanation counted as verified only when an AWS source or my own account confirmed it. Fluent is not the same as correct.

## The checks

| # | Question from the brief | What the AI said, in short | Checked against | Result |
|---|---|---|---|---|
| 1 | Explain cloud computing in simple terms | Renting computing over the internet and paying for use; elastic capacity; minutes instead of weeks | My account: `terraform apply` created 13 IAM resources in under 40 seconds (20:55:05 to 20:55:42 WAT) | Matches. A general definition, so the account run is the evidence |
| 2 | Explain the AWS Shared Responsibility Model | AWS secures the cloud itself; the customer secures what they put in it; the customer's share shrinks from EC2 to S3 | AWS *Shared Responsibility Model* page: "Security 'of' the Cloud versus Security 'in' the Cloud"; on EC2 "the customer [does] all of the necessary security configuration"; for S3 and DynamoDB "AWS operates the infrastructure layer, the operating system, and platforms" | Matches |
| 3 | Compare IaaS, PaaS and SaaS | Table of what you get, what you manage and an example of each | The same page names EC2 as IaaS. Product pages for the examples | **Two corrections** (below) |
| 4 | Explain IAM users, groups, roles and policies with examples | Users have long-term credentials; groups carry policies; roles give temporary credentials; everything is denied unless allowed, and an explicit Deny wins | *IAM roles*: a role "does not have standard long-term credentials"; *Policy evaluation*: "all requests are implicitly denied" and "an explicit deny overrides an explicit allow". **My account:** 19 simulated decisions in [`scripts/verify_live.sh`](../scripts/verify_live.sh), for example `ec2:DescribeInstances` is `allowed` with MFA and `explicitDeny` without | Matches, plus one caveat (below) |
| 5 | (my own follow-up) What does the Free Tier give a new account? | Credits rather than the old "12 months free" model | AWS *Free Tier* page and FAQs: US$100 in credits plus up to US$100 more, Free plan for up to 6 months | Matches, with one inconsistency in AWS's own FAQ (below) |

## What the checks changed

1. **Amazon Chime removed as a SaaS example.** The first draft of the comparison table listed it. AWS announced in 2025 that Chime would reach end of support in February 2026, so it is no longer a current example. The table now uses Amazon QuickSight and Microsoft 365.
2. **AWS Lambda moved out of the PaaS column.** The draft used Lambda as a PaaS example. AWS presents Lambda as serverless compute, which the common three-way split does not fit cleanly, so the table uses AWS Elastic Beanstalk and Amazon RDS instead, which are uncontroversial.
3. **"Use an IAM user" is a lab answer, not the production one.** The first item in AWS's *Security best practices in IAM* is "Require human users to use federation with an identity provider to access AWS using temporary credentials". The brief asks for an IAM user, so this lab creates one, with no access keys and MFA enforced. The README's Lab vs production table says that production would use IAM Identity Center, which is what I already use to run Terraform.
4. **The Free Tier answer carries a caveat.** The Free Tier FAQ says Free plan credits expire 6 months after the account is created, but its answer about the Paid plan says upgraded credits expire after 12 months. I report both rather than pick one.

## Sources

- https://aws.amazon.com/compliance/shared-responsibility-model/
- https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html
- https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html
- https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html
- https://aws.amazon.com/free/ and https://aws.amazon.com/free/free-tier-faqs/
- [docs/evidence/live-run-2026-11-13.txt](evidence/live-run-2026-11-13.txt): the full live simulation transcript
