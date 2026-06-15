# Session Prompt Template

Use this template to structure your opening prompt for each coding session.
A good prompt reduces back-and-forth and gets better results from the first response.

---

## Template

```
Context:
- Project: [name]
- Files involved: [list the specific files]
- Current state: [what works, what doesn't]

Task:
[Describe the specific thing you want done. Be concrete.]
[Include: what it should do, what it should NOT do, any constraints.]

Constraints:
- [e.g., "Stay within the existing auth module — don't refactor other files"]
- [e.g., "Don't add new dependencies"]
- [e.g., "Keep backward compatibility with the existing API"]

Definition of done:
- [e.g., "All existing tests still pass"]
- [e.g., "New endpoint returns 200 with the correct schema"]
- [e.g., "Error cases return appropriate HTTP status codes"]
```

---

## Example (Good)

```
Context:
- Project: customer-portal API
- Files: src/api/auth.py, tests/test_auth.py
- Current state: Login works. Password reset is not implemented yet.

Task:
Add a password reset flow:
1. POST /auth/reset-request — accepts email, sends reset token (mock email for now)
2. POST /auth/reset-confirm — accepts token + new password, updates user record

Constraints:
- Token should expire after 1 hour
- Tokens should be stored in the existing Redis instance (not a new table)
- Don't change the existing login endpoint

Definition of done:
- Both endpoints return correct HTTP codes (200, 400, 404 as appropriate)
- Reset token expires correctly (test this)
- All existing auth tests still pass
```

## Example (Poor — avoid this)

```
Add password reset
```

---

## For Mobile (Voice Input)

Dictate the key points and let the agent fill in details:

```
"Add password reset to the auth API. Two endpoints: 
request reset with email, and confirm reset with token and new password.
Store tokens in Redis, expire after one hour. Don't break existing login."
```
