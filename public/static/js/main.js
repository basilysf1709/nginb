document.addEventListener('DOMContentLoaded', () => {
    const button = document.getElementById('testButton');
    const messageElement = document.getElementById('message');

    if (button) {
        button.addEventListener('click', () => {
            if (messageElement) {
                messageElement.textContent = 'JavaScript is working! Button clicked.';
                console.log('Test button clicked.');
            }
        });
    } else {
        console.error('Test button not found.');
    }

    console.log('Zig server test JS loaded.');
});
