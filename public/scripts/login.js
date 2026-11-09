// login.js - Shows the error message after a failed owner login

const params = new URLSearchParams(window.location.search);
if (params.get('error')) {
    document.getElementById('login-error').hidden = false;
}
