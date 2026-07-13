# OAuth Logout Security Fix

## Security Issue

**Critical:** Users could logout and immediately login again WITHOUT entering credentials.

### Root Cause
- Backend logout only cleared the local Peoplemesh session cookie
- OAuth provider SSO sessions (Keycloak, Microsoft, Google) remained active
- Upon clicking "Sign In" after logout, the OAuth provider would automatically issue a new token without password prompt

## Fix Applied

### Changes Made

#### 1. Backend: `OAuthLoginResource.java`

**Added proper OIDC RP-Initiated Logout:**

```java
@GET
@POST
@Path("/logout")
public Response logout(@jakarta.ws.rs.CookieParam(SessionService.COOKIE_NAME) String sessionCookie)
```

**Provider-specific logout handling:**

| Provider | Logout Behavior |
|----------|-----------------|
| **Keycloak** | Redirects to `{issuer}/protocol/openid-connect/logout?post_logout_redirect_uri=...` |
| **Microsoft** | Redirects to `https://login.microsoftonline.com/common/oauth2/v2.0/logout?post_logout_redirect_uri=...` |
| **Google** | Local logout only (Google doesn't support single-app logout without signing out of ALL Google services) |

**How it works:**
1. Reads session cookie to determine which OAuth provider user logged in with
2. Clears Peoplemesh session cookie
3. If provider supports OIDC logout, redirects to provider's logout endpoint
4. Provider terminates SSO session
5. Provider redirects back to app homepage

#### 2. Frontend: `auth.js`

**Changed from API POST to navigation:**

```javascript
async logout() {
  if (this._isLoggingOut) return;
  this._isLoggingOut = true;
  // Clear local session state before redirecting
  this.setUser(null);
  // Navigate to logout endpoint - backend will redirect to OAuth provider logout
  // which terminates SSO session and redirects back to app
  window.location.href = "/api/v1/auth/logout";
}
```

**Why this change:**
- Backend now returns 303 redirect (not 204 No Content)
- Full page navigation required to follow OAuth logout redirect chain
- Simpler than async fetch + handling redirect

### Provider Logout Specifications

#### Keycloak
- **Endpoint:** `{issuer}/protocol/openid-connect/logout`
- **Query Params:** `post_logout_redirect_uri` (where to return after logout)
- **Behavior:** Terminates Keycloak SSO session, redirects back to app
- **Docs:** https://www.keycloak.org/docs/latest/securing_apps/#logout

#### Microsoft Azure AD
- **Endpoint:** `https://login.microsoftonline.com/common/oauth2/v2.0/logout`
- **Query Params:** `post_logout_redirect_uri` (where to return after logout)
- **Behavior:** Signs user out of Microsoft account, redirects back to app
- **Docs:** https://learn.microsoft.com/en-us/entra/identity-platform/v2-protocols-oidc#send-a-sign-out-request

#### Google
- **No OIDC logout endpoint** for single-app logout
- **Why:** Google's logout would sign user out of ALL Google services (Gmail, YouTube, etc.)
- **Best Practice:** Only clear local session
- **Behavior:** User must manually sign out from Google accounts if they want full logout
- **Docs:** https://developers.google.com/identity/protocols/oauth2/openid-connect#logout

### Testing the Fix

#### Before Fix (Security Issue):
1. Login with Keycloak (or Microsoft)
2. Click "Sign Out" → redirected to landing page
3. Click "Sign In" → **IMMEDIATELY logged back in without password**
4. ❌ **Security vulnerability**

#### After Fix (Expected Behavior):
1. Login with Keycloak (or Microsoft)
2. Click "Sign Out" → redirected to Keycloak/Microsoft logout → redirected to landing page
3. Click "Sign In" → **Prompted for username and password**
4. ✅ **Secure logout**

### Deployment Steps

1. **Rebuild peoplemesh image** with the code changes:
   ```bash
   cd /Users/psamouel/Documents/peoplemesh
   # Build and push to quay.io/rh-ai-quickstart/peoplemesh:latest
   ```

2. **Redeploy with Helm:**
   ```bash
   # Force pod restart to pull new image
   kubectl rollout restart deployment/peoplemesh -n samouelian-peoplemesh
   
   # Or force helm upgrade
   helm upgrade peoplemesh peoplemesh-umbrella \
     --namespace samouelian-peoplemesh \
     --reuse-values \
     --force
   ```

3. **Test logout:**
   - Login with testuser
   - Click user menu → Sign Out
   - Should redirect to Keycloak logout page briefly
   - Then redirect back to app landing page
   - Click "Sign In" → **Should prompt for password**

### Files Modified

**Backend:**
- `/Users/psamouel/Documents/peoplemesh/src/main/java/org/peoplemesh/api/resource/OAuthLoginResource.java`

**Frontend:**
- `/Users/psamouel/Documents/peoplemesh/src/main/web/assets/js/auth.js`

### Additional Security Considerations

1. **Session Duration:** Sessions expire after 7 days (`SESSION_TTL_SECONDS = 60*60*24*7`)
2. **Session Cookie Flags:**
   - `HttpOnly: true` - Prevents JavaScript access
   - `Secure: true` - HTTPS only (when accessed via HTTPS)
   - `SameSite: LAX` - CSRF protection
3. **HMAC-signed cookies:** Sessions are cryptographically signed to prevent tampering
4. **Provider session lifetimes:** Each OAuth provider has its own session timeout (independent of Peoplemesh)

### Known Limitations

1. **Google logout:** Only clears Peoplemesh session, not Google SSO session
   - This is by design (Google doesn't support single-app logout)
   - User must manually logout from google.com if they want full logout

2. **Session tracking:** Provider is stored in session cookie
   - If cookie is corrupted/missing, defaults to local logout only
   - Not an issue in practice (corrupted session = already logged out)

3. **Multi-provider scenarios:** If user has sessions with multiple providers
   - Only logs out from the provider they used for current session
   - Other provider sessions remain (rare edge case)

## References

- [OIDC RP-Initiated Logout Spec](https://openid.net/specs/openid-connect-rpinitiated-1_0.html)
- [Keycloak Logout Documentation](https://www.keycloak.org/docs/latest/securing_apps/#logout)
- [Microsoft Azure AD Logout](https://learn.microsoft.com/en-us/entra/identity-platform/v2-protocols-oidc#send-a-sign-out-request)
- [Google OAuth2 Logout Considerations](https://developers.google.com/identity/protocols/oauth2/openid-connect#logout)
