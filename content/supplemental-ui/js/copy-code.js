;(function () {
  var COPY_LANGS = { bash: true, sh: true, shell: true, console: true, yaml: true, yml: true }

  function isBashBlock (block) {
    var el = block.querySelector('code')
    if (!el) return false
    if (COPY_LANGS[el.getAttribute('data-lang')]) return true
    return /(^|\s)language-(bash|sh|shell|console|yaml|yml)(\s|$)/.test(el.className || '')
  }

  function sourceText (block) {
    var code = block.querySelector('code')
    if (!code) return ''
    return (code.innerText || code.textContent || '').replace(/\n$/, '')
  }

  function setCopied (btn) {
    var original = btn.getAttribute('data-label') || 'Copiar'
    btn.textContent = 'Copiado'
    btn.classList.add('is-copied')
    window.setTimeout(function () {
      btn.textContent = original
      btn.classList.remove('is-copied')
    }, 1600)
  }

  function copyText (text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text)
    }
    return new Promise(function (resolve, reject) {
      var area = document.createElement('textarea')
      area.value = text
      area.setAttribute('readonly', '')
      area.style.position = 'fixed'
      area.style.left = '-9999px'
      document.body.appendChild(area)
      area.select()
      try {
        document.execCommand('copy')
        resolve()
      } catch (err) {
        reject(err)
      } finally {
        document.body.removeChild(area)
      }
    })
  }

  function addButtons () {
    document.querySelectorAll('.listingblock').forEach(function (block) {
      if (!isBashBlock(block)) return
      if (block.querySelector('.lab-copy-btn')) return

      var host = block.querySelector('pre')
      if (!host) return
      host.classList.add('has-copy-button')

      var btn = document.createElement('button')
      btn.type = 'button'
      btn.className = 'lab-copy-btn'
      btn.setAttribute('data-label', 'Copiar')
      btn.setAttribute('aria-label', 'Copiar comando')
      btn.textContent = 'Copiar'
      host.appendChild(btn)

      btn.addEventListener('click', function (event) {
        event.preventDefault()
        copyText(sourceText(block)).then(function () {
          setCopied(btn)
        }).catch(function () {
          btn.textContent = 'Error'
        })
      })
    })
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', addButtons)
  } else {
    addButtons()
  }
})()
