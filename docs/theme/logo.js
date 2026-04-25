document.addEventListener('DOMContentLoaded', function () {
    const sidebar = document.querySelector('#mdbook-sidebar');
    if (!sidebar) return;

    const logo = document.createElement('div');
    logo.style.cssText = 'position:absolute;top:0;left:0;right:0;z-index:1;padding:14px 16px 10px;background-color:var(--sidebar-bg);';
    logo.innerHTML = '<a href="index.html"><img src="assets/lockup-dark.svg" alt="Cerulean" style="width:100%;max-width:250px;height:auto;display:block"></a>';
    sidebar.insertBefore(logo, sidebar.firstChild);

    const img = logo.querySelector('img');
    function pushTocDown() {
        const height = logo.offsetHeight;
        const iframe = sidebar.querySelector('.sidebar-iframe-outer');
        const scrollbox = sidebar.querySelector('.sidebar-scrollbox');
        if (iframe) iframe.style.top = height + 'px';
        if (scrollbox) scrollbox.style.top = height + 'px';
    }

    img.addEventListener('load', pushTocDown);
    // SVGs report dimensions without a load event in some browsers
    if (img.complete) pushTocDown();
});
