;(function () {
  var BASH_LANGS = { bash: true, sh: true, shell: true, console: true }

  function isBashBlock (block) {
    var el = block.querySelector('code') || block.querySelector('pre')
    if (!el) return false
    var lang = ((el.getAttribute('data-lang') || '') + ' ' + (el.className || '')).toLowerCase()
    if (BASH_LANGS[el.getAttribute('data-lang')]) return true
    return /(^|\s)language-(bash|sh|shell|console)(\s|$)/.test(el.className || '') ||
      /\b(bash|sh|shell|console)\b/.test(lang)
  }

  function sourceText (block) {
    var pre = block.querySelector('pre')
    if (!pre) return ''
    return (pre.innerText || pre.textContent || '').replace(/\n$/, '')
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
      if (block.querySelector('.copy-button')) return

      var host = block.querySelector('pre') || block.querySelector('.content') || block
      host.classList.add('has-copy-button')

      var btn = document.createElement('button')
      btn.type = 'button'
      btn.className = 'copy-button'
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
