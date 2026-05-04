document.addEventListener('DOMContentLoaded', function () {
    const sidebar = document.querySelector('#mdbook-sidebar');
    if (!sidebar) return;
    const scrollbox = sidebar.querySelector('.sidebar-scrollbox');
    if (!scrollbox) return;

    const logo = document.createElement('div');
    logo.className = 'cerulean-logo';
    logo.innerHTML = '<a href="index.html"><img src="assets/lockup-dark.svg" alt="Cerulean"></a>';
    scrollbox.insertBefore(logo, scrollbox.firstChild);
});
